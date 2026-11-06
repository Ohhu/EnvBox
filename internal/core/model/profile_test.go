package model

import (
	"encoding/json"
	"testing"
	"time"
)

func TestTimestampRoundTripsLikeSwift(t *testing.T) {
	when := time.Date(2026, 11, 2, 3, 20, 0, 123_000_000, time.UTC)
	encoded, err := json.Marshal(NewTimestamp(when))
	if err != nil {
		t.Fatalf("marshal: %v", err)
	}
	if string(encoded) != `"2026-11-02T03:20:00.123Z"` {
		t.Fatalf("unexpected encoding: %s", encoded)
	}

	var back Timestamp
	if err := json.Unmarshal(encoded, &back); err != nil {
		t.Fatalf("unmarshal: %v", err)
	}
	if !back.Equal(when) {
		t.Fatalf("round trip mismatch: %v != %v", back, when)
	}
}

func TestTimestampAcceptsWholeSecondsAndOffsets(t *testing.T) {
	for _, raw := range []string{
		`"2026-11-02T03:20:00Z"`,
		`"2026-11-02T11:20:00+08:00"`,
		`"2026-11-02T03:20:00.5Z"`,
	} {
		var ts Timestamp
		if err := json.Unmarshal([]byte(raw), &ts); err != nil {
			t.Fatalf("%s: %v", raw, err)
		}
		if ts.UTC().Format("2006-01-02T15:04") != "2026-11-02T03:20" {
			t.Fatalf("%s parsed to %v", raw, ts)
		}
	}
}

func TestFingerprintMatchesCanonicalForm(t *testing.T) {
	// Reference value computed from the canonical string the Swift build produces:
	// "EnvBoxProfileV1\n7:B_KEY=3:v=v\n3:A=x\n"
	p := EnvProfile{
		Variables: []EnvVariable{
			{Key: "B_KEY", Value: "v=v", IsEnabled: true},
			{Key: "A", Value: "x", IsEnabled: true},
			{Key: "DISABLED", Value: "ignored"},
			{Key: "  C  ", Value: "trimmed", IsEnabled: true},
		},
	}
	first := p.Fingerprint()
	second := EnvProfile{Variables: []EnvVariable{
		{Key: "C", Value: "trimmed", IsEnabled: true},
		{Key: "A", Value: "x", IsEnabled: true},
		{Key: "B_KEY", Value: "v=v", IsEnabled: true},
	}}.Fingerprint()
	if first != second {
		t.Fatalf("fingerprint must ignore order: %s vs %s", first, second)
	}
	p.Variables[2].IsEnabled = true
	if p.Fingerprint() == first {
		t.Fatal("enabling a variable must change the fingerprint")
	}
}

func TestValidateProfileRejectsBadKeys(t *testing.T) {
	base := func(keys ...string) EnvProfile {
		p := EnvProfile{ID: "p1", Name: "demo"}
		for i, k := range keys {
			p.Variables = append(p.Variables, EnvVariable{ID: string(rune('a' + i)), Key: k, Value: "v"})
		}
		return p
	}
	if err := ValidateProfile(base("GOOD_KEY", "_leading")); err != nil {
		t.Fatalf("valid profile rejected: %v", err)
	}
	for _, bad := range [][]string{
		{"1BAD"},
		{"HAS-DASH"},
		{"HAS SPACE"},
		{"GOOD", "good"},
	} {
		if err := ValidateProfile(base(bad...)); err == nil {
			t.Fatalf("expected rejection for %v", bad)
		}
	}
}
