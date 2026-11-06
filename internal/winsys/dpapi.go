//go:build windows

package winsys

import (
	"errors"
	"unsafe"
)

type dataBlob struct {
	cbData uint32
	pbData *byte
}

func newBlob(b []byte) dataBlob {
	var p *byte
	if len(b) > 0 {
		p = &b[0]
	}
	return dataBlob{cbData: uint32(len(b)), pbData: p}
}

func copyAndFree(out *dataBlob) []byte {
	defer procLocalFree.Call(uintptr(unsafe.Pointer(out.pbData)))
	if out.cbData == 0 || out.pbData == nil {
		return nil
	}
	return append([]byte(nil), unsafe.Slice(out.pbData, out.cbData)...)
}

const cryptProtectUIForbidden = 0x1

// Protect seals data with the current user's DPAPI key. The ciphertext can only
// be decrypted by the same user on the same machine (or with a roaming profile).
func Protect(data []byte) ([]byte, error) {
	in := newBlob(data)
	var out dataBlob
	ret, _, _ := procCryptProtectData.Call(
		uintptr(unsafe.Pointer(&in)), 0, 0, 0, 0, cryptProtectUIForbidden,
		uintptr(unsafe.Pointer(&out)),
	)
	if ret == 0 {
		return nil, errors.New("winsys: 无法加密本机密钥，请确认当前用户配置可用")
	}
	return copyAndFree(&out), nil
}

// Unprotect reverses Protect.
func Unprotect(sealed []byte) ([]byte, error) {
	in := newBlob(sealed)
	var out dataBlob
	ret, _, _ := procCryptUnprotectData.Call(
		uintptr(unsafe.Pointer(&in)), 0, 0, 0, 0, cryptProtectUIForbidden,
		uintptr(unsafe.Pointer(&out)),
	)
	if ret == 0 {
		return nil, errors.New("winsys: 无法解密本机密钥，它可能是在其他用户账户下创建的")
	}
	return copyAndFree(&out), nil
}
