//go:build windows

package main

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/Ohhu/EnvBox/internal/apperr"
)

// The frontend talks to the backend over two JSON endpoints instead of generated
// bindings: /api/state for the first render and /api/dispatch for actions. One
// code path, testable with httptest, and no codegen step in the build.
func newHandler(service *App, assets http.Handler) http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("/api/state", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			writeJSON(w, http.StatusMethodNotAllowed, Payload{OK: false, Message: "只支持 GET"})
			return
		}
		state, err := service.State()
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Payload{OK: false, Message: apperr.User(err)})
			return
		}
		writeJSON(w, http.StatusOK, Payload{OK: true, State: state})
	})

	mux.HandleFunc("/api/dispatch", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			writeJSON(w, http.StatusMethodNotAllowed, Payload{OK: false, Message: "只支持 POST"})
			return
		}
		var request struct {
			Action  string `json:"action"`
			Payload string `json:"payload"`
		}
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 1<<20)).Decode(&request); err != nil {
			writeJSON(w, http.StatusBadRequest, Payload{OK: false, Message: "请求格式错误"})
			return
		}
		payload, err := service.Dispatch(request.Action, request.Payload)
		if err != nil {
			writeJSON(w, http.StatusInternalServerError, Payload{OK: false, Message: apperr.User(err)})
			return
		}
		status := http.StatusOK
		if !payload.OK {
			status = http.StatusBadRequest
		}
		writeJSON(w, status, payload)
	})

	mux.Handle("/", assets)
	return noStore(mux)
}

// noStore keeps the webview from caching API answers and stale assets.
func noStore(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if strings.HasPrefix(r.URL.Path, "/api/") {
			w.Header().Set("Cache-Control", "no-store")
		}
		next.ServeHTTP(w, r)
	})
}

func writeJSON(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json; charset=utf-8")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
