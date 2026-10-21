package ledger

import (
	"path/filepath"
	"reflect"
	"testing"
)

func TestLedgerPersistsAndForgets(t *testing.T) {
	path := filepath.Join(t.TempDir(), "devices.json")
	l, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if err := l.Add("devA", "1"); err != nil {
		t.Fatal(err)
	}
	_ = l.Add("devA", "4")
	_ = l.Add("devB", "2")

	again, err := Open(path)
	if err != nil {
		t.Fatal(err)
	}
	if got := again.Keys("devA"); !reflect.DeepEqual(got, []string{"1", "4"}) {
		t.Fatalf("devA keys after reopen: %v", got)
	}
	if got := again.Stale([]string{"devB"}); !reflect.DeepEqual(got, []string{"devA"}) {
		t.Fatalf("stale: %v", got)
	}
	if err := again.Forget("devA"); err != nil {
		t.Fatal(err)
	}
	third, _ := Open(path)
	if got := third.Devices(); !reflect.DeepEqual(got, []string{"devB"}) {
		t.Fatalf("devices after forget: %v", got)
	}
}
