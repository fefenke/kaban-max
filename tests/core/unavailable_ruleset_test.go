package rule

import (
	"context"
	"github.com/sagernet/sing-box/adapter"
	"github.com/sagernet/sing-box/option"
	"github.com/sagernet/sing/common/json"
	M "github.com/sagernet/sing/common/metadata"
	"github.com/sagernet/sing/service"
	"github.com/stretchr/testify/require"
	"testing"
	"time"
)

func TestKabanmaxUnavailableSetDoesNotDisappear(t *testing.T) {
	manager := new(missingDetourOutboundManager)
	ctx := service.ContextWith[adapter.OutboundManager](context.Background(), manager)
	var opts option.RuleSet
	require.NoError(t, json.Unmarshal([]byte(`{"type":"remote","tag":"protected","format":"source","url":"https://rules.example/protected.srs","http_client":{"detour":"vpn"}}`), &opts))
	set := newRemoteDownloadForTest(t, ctx, opts)
	require.NoError(t, set.StartContext(ctx, adapter.NewHTTPStartContext()))
	defer set.Close()
	item := &RuleSetItem{setList: []adapter.RuleSet{set}}
	metadata := &adapter.InboundContext{Destination: M.ParseSocksaddr("198.51.100.7:443")}
	require.True(t, item.Match(metadata), "an unavailable protected set must not silently miss and permit lower Direct rules")
	require.Equal(t, "protected", metadata.UnavailableRuleSet)
	metadata.QueryType = 1
	require.False(t, item.Match(metadata), "DNS query matching must retain its existing semantics")
	// A later successful download restores normal matching without a restart.
	require.NoError(t, set.loadBytes([]byte(`{"version":3,"rules":[{"ip_cidr":["203.0.113.0/24"]}]}`), time.Now(), ""))
	metadata = &adapter.InboundContext{Destination: M.ParseSocksaddr("198.51.100.7:443")}
	require.False(t, item.Match(metadata))
	require.Empty(t, metadata.UnavailableRuleSet)
	require.Zero(t, manager.defaultCalls)
}
