// Command sill-tailnet is the C-archive entry point for Sill for iPhone and
// iPad: SillTailnet.xcframework (Scripts/make-tailnet.sh). Ported from
// Frigate Launcher's nvr_tailnet.go.
//
// gomobile is deliberately not used: it generates bindings for a Go API far
// larger than the handful of calls below, and tracks Xcode releases on its own
// schedule. Everything crosses as JSON, and every string returned must be
// released with SillTailnetFreeString.
package main

/*
#include <stdlib.h>
*/
import "C"

import (
	"encoding/json"
	"unsafe"

	"getsill.app/tailnet-mobile/tailnet"
)

// The single controller for the process: one app instance, one state dir.
var controller = tailnet.New()

// SillTailnetStart brings the tailnet up from a JSON config
// ({"fingerprint","preauthKey","domain","stateDir","hostname"}). Returns
// {"ok":true} or {"ok":false,"error":"..."}; everything after that is
// observed through SillTailnetStatus.
//
//export SillTailnetStart
func SillTailnetStart(cfgJSON *C.char) *C.char {
	var cfg tailnet.Config
	if err := json.Unmarshal([]byte(C.GoString(cfgJSON)), &cfg); err != nil {
		return C.CString(`{"ok":false,"error":"could not decode the start configuration"}`)
	}
	if err := controller.Start(cfg); err != nil {
		out, _ := json.Marshal(map[string]any{"ok": false, "error": controller.Status().Error})
		return C.CString(string(out))
	}
	return C.CString(`{"ok":true}`)
}

// SillTailnetStatus returns the current status as JSON.
//
//export SillTailnetStatus
func SillTailnetStatus() *C.char {
	return C.CString(controller.StatusJSON())
}

// SillTailnetRecover gets the path to the Mac working again, cheapest fix
// first. Returns {"started":bool}.
//
//export SillTailnetRecover
func SillTailnetRecover() *C.char {
	out, _ := json.Marshal(map[string]any{"started": controller.Recover("")})
	return C.CString(string(out))
}

// SillTailnetSuspend releases the loopback listeners before iOS suspends the
// app, remembering their ports.
//
//export SillTailnetSuspend
func SillTailnetSuspend() { controller.Suspend() }

// SillTailnetResume rebinds what Suspend released, on the same ports where
// it can. Idempotent.
//
//export SillTailnetResume
func SillTailnetResume() { controller.Resume() }

// SillTailnetStop tears the tailnet down. Idempotent.
//
//export SillTailnetStop
func SillTailnetStop() { controller.Stop() }

// SillTailnetFreeString releases a string returned by any function above.
//
//export SillTailnetFreeString
func SillTailnetFreeString(s *C.char) {
	if s != nil {
		C.free(unsafe.Pointer(s))
	}
}

func main() {}
