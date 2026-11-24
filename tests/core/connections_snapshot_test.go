package clashapi

import (
    "testing"
    "time"
    "github.com/sagernet/sing-box/common/trafficcontrol"
    C "github.com/sagernet/sing-box/constant"
    "github.com/gofrs/uuid/v5"
)

// Test the selection before serializing: input count must not determine output allocation.
func TestBoundedConnectionSelection(t *testing.T) {
    items := make([]*trafficcontrol.TrackerMetadata, 10000)
    for i := range items {
        items[i] = &trafficcontrol.TrackerMetadata{ID: uuid.Must(uuid.NewV4()), CreatedAt: time.Unix(int64(i), 0)}
    }
    visit := func(fn func(*trafficcontrol.TrackerMetadata)) { for _, item := range items { fn(item) } }
    selected, total := selectConnectionSnapshot(visit, 200)
    if total != 10000 || len(selected) != 200 { t.Fatalf("selected=%d total=%d", len(selected), total) }
    if selected[0].CreatedAt.Unix() != 9999 || selected[199].CreatedAt.Unix() != 9800 { t.Fatal("must retain newest records deterministically") }
    items[9999].OutboundType = C.TypeDNS
    selected, total = selectConnectionSnapshot(visit, 200)
    if total != 9999 || selected[0].CreatedAt.Unix() != 9998 { t.Fatal("DNS trackers must be excluded before selection and counting") }
    empty, total := selectConnectionSnapshot(visit, 0)
    if len(empty) != 0 || total != 9999 { t.Fatal("count-only snapshots must not retain trackers") }
}
