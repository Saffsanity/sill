//go:build tools

// Package tools pins the third-party binaries Sill for Mac bundles, so their
// versions and checksums live in this go.mod and go.sum and every build of
// Sill.app gets the same Headscale (Scripts/make-helpers.sh builds it from
// here with `go build`, never `go install …@latest`).
package tools

import _ "github.com/juanfont/headscale/cmd/headscale"
