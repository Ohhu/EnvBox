package portable

import (
	"encoding/json"
	"testing"

	"github.com/Ohhu/EnvBox/internal/cryptox"
	"github.com/Ohhu/EnvBox/internal/model"
)

func sampleProfiles() []model.EnvProfile {
	return []model.EnvProfile{
		{
			ID: "8D2E4C11-0000-4000-8000-000000000001", Name: "工作", Note: "n", Tint: "ocean",
			Symbol: "briefcase.fill",
			Variables: []model.EnvVariable{
				{ID: "a", Key: "API_TOKEN", Value: "s3cret", IsEnabled: true, IsSecret: true},
				{ID: "b", Key: "REGION", Value: "cn-north-1", IsEnabled: true},
			},
			CreatedAt: model.Now(), UpdatedAt: model.Now(),
		},
	}
}

func TestExportImportRoundTrip(t *testing.T) {
	// Keep iterations low so the test stays fast; the envelope carries its own value.
	data, err := Export(sampleProfiles(), "correct horse battery", 100_000, model.Now())
	if err != nil {
		t.Fatalf("export: %v", err)
	}

	var envelope model.ExportEnvelope
	if err := json.Unmarshal(data, &envelope); err != nil {
		t.Fatalf("envelope: %v", err)
	}
	if envelope.Format != model.ExportFormat || envelope.KDF != model.ExportKDF {
		t.Fatalf("unexpected envelope %+v", envelope)
	}

	back, err := Import(data, "correct horse battery")
	if err != nil {
		t.Fatalf("import: %v", err)
	}
	if len(back.Profiles) != 1 || back.Profiles[0].Name != "工作" {
		t.Fatalf("unexpected payload %+v", back.Profiles)
	}
	if back.Profiles[0].Variables[0].Value != "s3cret" {
		t.Fatalf("value mismatch")
	}
	if back.ExportedAt.Time.IsZero() {
		t.Fatal("exportedAt must survive the round trip")
	}
}

func TestImportRejectsWrongPassphraseAndTampering(t *testing.T) {
	data, err := Export(sampleProfiles(), "correct horse battery", 100_000, model.Now())
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Import(data, "wrong passphrase"); err == nil {
		t.Fatal("expected wrong passphrase to fail")
	}

	var envelope model.ExportEnvelope
	if err := json.Unmarshal(data, &envelope); err != nil {
		t.Fatal(err)
	}
	envelope.Sealed[0] ^= 0xFF
	tampered, err := json.Marshal(envelope)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Import(tampered, "correct horse battery"); err == nil {
		t.Fatal("expected tamper detection")
	}
}

func TestImportRejectsDowngradedIterations(t *testing.T) {
	data, err := Export(sampleProfiles(), "correct horse battery", 100_000, model.Now())
	if err != nil {
		t.Fatal(err)
	}
	var envelope model.ExportEnvelope
	if err := json.Unmarshal(data, &envelope); err != nil {
		t.Fatal(err)
	}
	envelope.Iterations = cryptox.MinIterations - 1
	downgraded, err := json.Marshal(envelope)
	if err != nil {
		t.Fatal(err)
	}
	if _, err := Import(downgraded, "correct horse battery"); err == nil {
		t.Fatal("expected iteration downgrade to be rejected")
	}
}

func TestAADIsStable(t *testing.T) {
	// Pinned so an accidental edit cannot silently break macOS compatibility.
	salt := []byte{0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15}
	got := string(AAD("envbox.export", 1, "PBKDF2-HMAC-SHA256", 600000, salt))
	want := "EnvBox.Export.v1|format=envbox.export|version=1|kdf=PBKDF2-HMAC-SHA256|iterations=600000|salt=AAECAwQFBgcICQoLDA0ODw=="
	if got != want {
		t.Fatalf("AAD drift:\n got %s\nwant %s", got, want)
	}
}
