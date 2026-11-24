package fakeip

import (
	"github.com/stretchr/testify/require"
	"net/netip"
	"testing"
)

func TestKabanmaxIPv6PrefixMigrationPreservesIPv4AndBoundsPool(t *testing.T) {
	storage := newFakeStorage()
	old := newTestStore(t, storage, "198.18.0.0/16", "fc00::/112")
	old4 := mustCreate(t, old, "keep.example")
	old6, err := old.Create("move.example", true)
	require.NoError(t, err)
	require.NoError(t, old.Close())
	current := newTestStore(t, storage, "198.18.0.0/16", "2001:2::/112")
	require.Equal(t, old4, mustCreate(t, current, "keep.example"))
	_, found := current.Lookup(old6)
	require.False(t, found)
	next, err := current.Create("move.example", true)
	require.NoError(t, err)
	require.True(t, netip.MustParsePrefix("2001:2::/112").Contains(next))
	require.False(t, netip.MustParsePrefix("fc00::/7").Contains(next))
	require.LessOrEqual(t, current.pool6.usable(), uint32(65536))
	require.False(t, current.Contains(old6))
	require.NoError(t, current.Close())
	again := newTestStore(t, storage, "198.18.0.0/16", "2001:2::/112")
	saved, err := again.Create("move.example", true)
	require.NoError(t, err)
	require.Equal(t, next, saved)
}
