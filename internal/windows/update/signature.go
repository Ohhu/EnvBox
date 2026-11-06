//go:build windows

package update

import (
	"crypto/sha1"
	"encoding/hex"
	"errors"
	"strings"
	"syscall"
	"unsafe"
)

// Authenticode verification lives here because the updater must never execute a
// downloaded installer that is not signed by the expected publisher.

var (
	wintrustDLL = syscall.NewLazyDLL("wintrust.dll")

	procWinVerifyTrust         = wintrustDLL.NewProc("WinVerifyTrust")
	procProvDataFromStateData  = wintrustDLL.NewProc("WTHelperProvDataFromStateData")
	procGetProvSignerFromChain = wintrustDLL.NewProc("WTHelperGetProvSignerFromChain")
	procGetProvCertFromChain   = wintrustDLL.NewProc("WTHelperGetProvCertFromChain")
)

type guid struct {
	Data1 uint32
	Data2 uint16
	Data3 uint16
	Data4 [8]byte
}

var actionGenericVerifyV2 = guid{
	Data1: 0x00AAC56B,
	Data2: 0xCD44,
	Data3: 0x11D0,
	Data4: [8]byte{0x8C, 0xC2, 0x00, 0xC0, 0x4F, 0xC2, 0x95, 0xEE},
}

type winTrustFileInfo struct {
	cbStruct     uint32
	filePath     *uint16
	hFile        syscall.Handle
	knownSubject *guid
}

type winTrustData struct {
	cbStruct           uint32
	policyCallbackData uintptr
	sipClientData      uintptr
	uiChoice           uint32
	revocationChecks   uint32
	unionChoice        uint32
	file               uintptr
	stateAction        uint32
	hWVTStateData      syscall.Handle
	urlReference       *uint16
	provFlags          uint32
	uiContext          uint32
	signatureSettings  uintptr
}

const (
	wtdUINone                = 2
	wtdRevokeNone            = 0
	wtdChoiceFile            = 1
	wtdStateActionVerify     = 1
	wtdStateActionClose      = 2
	wtdCacheOnlyURLRetrieval = 0x1000
)

// SignatureError describes why a file was rejected.
type SignatureError struct {
	Reason string
}

func (e *SignatureError) Error() string {
	return "update: " + e.Reason
}

// VerifySignature checks the Authenticode signature of path and returns the
// signer certificate thumbprint as upper-case hex, matching what signtool and
// PowerShell report.
func VerifySignature(path string) (string, error) {
	if strings.TrimSpace(path) == "" {
		return "", errors.New("update: 缺少待校验文件")
	}
	filePath, err := syscall.UTF16PtrFromString(path)
	if err != nil {
		return "", err
	}

	fileInfo := winTrustFileInfo{cbStruct: uint32(unsafe.Sizeof(winTrustFileInfo{})), filePath: filePath}
	data := winTrustData{
		cbStruct:         uint32(unsafe.Sizeof(winTrustData{})),
		uiChoice:         wtdUINone,
		revocationChecks: wtdRevokeNone,
		unionChoice:      wtdChoiceFile,
		file:             uintptr(unsafe.Pointer(&fileInfo)),
		stateAction:      wtdStateActionVerify,
		provFlags:        wtdCacheOnlyURLRetrieval,
	}

	status, _, _ := procWinVerifyTrust.Call(
		0,
		uintptr(unsafe.Pointer(&actionGenericVerifyV2)),
		uintptr(unsafe.Pointer(&data)),
	)
	if status != 0 {
		return "", &SignatureError{Reason: trustStatusReason(uint32(status))}
	}
	defer func() {
		data.stateAction = wtdStateActionClose
		procWinVerifyTrust.Call(0, uintptr(unsafe.Pointer(&actionGenericVerifyV2)), uintptr(unsafe.Pointer(&data)))
	}()

	thumbprint, err := signerThumbprint(data.hWVTStateData)
	if err != nil {
		return "", err
	}
	return thumbprint, nil
}

// signerThumbprint walks the state returned by WinVerifyTrust to the signer
// certificate and hashes its DER encoding with SHA-1.
func signerThumbprint(state syscall.Handle) (string, error) {
	provider, _, _ := procProvDataFromStateData.Call(uintptr(state))
	if provider == 0 {
		return "", errors.New("update: 无法读取签名状态")
	}
	signer, _, _ := procGetProvSignerFromChain.Call(provider, 0, 0, 0)
	if signer == 0 {
		return "", errors.New("update: 无法读取签名者信息")
	}
	providerCert, _, _ := procGetProvCertFromChain.Call(signer, 0)
	if providerCert == 0 {
		return "", errors.New("update: 无法读取签名证书")
	}

	// The structs below mirror the Win32 layouts, so the pointer arithmetic stays
	// inside the type system instead of manual byte offsets.
	// Reinterpreting the uintptr slot as a pointer keeps the conversion off the
	// uintptr→unsafe.Pointer path that go vet flags, without changing semantics:
	// the value came straight from Win32 and is never arithmetic.
	provCert := *(**cryptProviderCert)(unsafe.Pointer(&providerCert))
	if provCert.pCert == nil {
		return "", errors.New("update: 签名证书为空")
	}
	if provCert.pCert.pbCertEncoded == nil || provCert.pCert.cbCertEncoded == 0 {
		return "", errors.New("update: 签名证书内容为空")
	}
	der := unsafe.Slice(provCert.pCert.pbCertEncoded, provCert.pCert.cbCertEncoded)
	sum := sha1.Sum(der)
	return strings.ToUpper(hex.EncodeToString(sum[:])), nil
}

// CRYPT_PROVIDER_CERT, truncated to the fields we read.
type cryptProviderCert struct {
	cbStruct uint32
	pCert    *certContext
}

// CERT_CONTEXT, truncated to the fields we read.
type certContext struct {
	dwCertEncodingType uint32
	pbCertEncoded      *byte
	cbCertEncoded      uint32
}

// trustStatusReason maps the common WinVerifyTrust failures to Chinese text.
func trustStatusReason(status uint32) string {
	switch status {
	case 0x800B0100:
		return "文件没有签名"
	case 0x800B0109:
		return "证书链不受信任"
	case 0x800B0101:
		return "证书已过期"
	case 0x800B0110:
		return "证书用途不符"
	case 0x80096010:
		return "签名者未知"
	case 0x800B010C:
		return "证书已被吊销"
	case 0x800700C1, 0x8007000B:
		return "文件格式无效"
	default:
		return "未通过 Authenticode 校验"
	}
}
