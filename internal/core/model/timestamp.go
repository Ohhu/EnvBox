package model

import (
	"fmt"
	"strconv"
	"time"
)

// layout matches Swift's ISO8601DateFormatter with
// [.withInternetDateTime, .withFractionalSeconds], which always emits
// millisecond precision and a trailing "Z".
const layout = "2006-01-02T15:04:05.000Z"

// Timestamp is a time.Time that round-trips through the same ISO-8601 shape the
// macOS build writes. Getting this wrong silently breaks cross-platform import.
type Timestamp struct {
	time.Time
}

// NewTimestamp wraps t.
func NewTimestamp(t time.Time) Timestamp { return Timestamp{Time: t} }

// Now returns the current UTC time as a Timestamp.
func Now() Timestamp { return Timestamp{Time: time.Now().UTC()} }

// ISO8601 renders the wire form used by MarshalJSON, for views that expose the
// timestamp as a plain string field.
func (t Timestamp) ISO8601() string {
	if t.Time.IsZero() {
		return "0001-01-01T00:00:00.000Z"
	}
	return t.UTC().Format(layout)
}

// MarshalJSON renders millisecond precision UTC.
func (t Timestamp) MarshalJSON() ([]byte, error) {
	if t.Time.IsZero() {
		return []byte(strconv.Quote("0001-01-01T00:00:00.000Z")), nil
	}
	return []byte(strconv.Quote(t.UTC().Format(layout))), nil
}

// UnmarshalJSON accepts both fractional and whole-second ISO-8601, with either
// "Z" or a numeric offset, because the macOS side accepts the same variants.
func (t *Timestamp) UnmarshalJSON(data []byte) error {
	raw, err := strconv.Unquote(string(data))
	if err != nil {
		return fmt.Errorf("model: 时间戳不是 JSON 字符串: %w", err)
	}
	if raw == "" {
		t.Time = time.Time{}
		return nil
	}
	for _, candidate := range []string{time.RFC3339Nano, time.RFC3339, layout} {
		if parsed, err := time.Parse(candidate, raw); err == nil {
			t.Time = parsed.UTC()
			return nil
		}
	}
	return fmt.Errorf("model: 无法解析时间戳 %q", raw)
}
