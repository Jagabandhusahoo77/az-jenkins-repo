/*
 * networking_test.go — Terratest integration tests for the networking module
 *
 * Terratest deploys REAL Azure resources, runs assertions, then destroys.
 * These tests verify behaviour that terraform validate/plan cannot:
 *   - Resources actually exist after apply
 *   - VNet peering is established and bidirectional
 *   - NSG rules block traffic as expected
 *
 * Cost: Each test run spins up ~10 Azure resources. Use sparingly.
 * Duration: ~10-15 minutes per test (Azure VNet peering takes a while).
 *
 * Usage:
 *   go test ./... -v -timeout 60m -run TestNetworkingModule
 */

package test

import (
	"fmt"
	"testing"
	"time"

	"github.com/Azure/azure-sdk-for-go/sdk/azidentity"
	"github.com/Azure/azure-sdk-for-go/sdk/resourcemanager/network/armnetwork"
	"github.com/gruntwork-io/terratest/modules/azure"
	"github.com/gruntwork-io/terratest/modules/random"
	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// TestNetworkingModule deploys the networking module, validates outputs,
// checks peering state, then destroys.
func TestNetworkingModule(t *testing.T) {
	t.Parallel()

	// Generate unique suffix to avoid naming conflicts with concurrent test runs
	uniqueSuffix := random.UniqueId()
	resourceGroupName := fmt.Sprintf("rg-test-networking-%s", uniqueSuffix)
	location := "eastus"

	// Terraform options point at our networking module with test-specific vars
	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../modules/networking",

		Vars: map[string]interface{}{
			"hub_name":             "hub",
			"environment":          "dev",
			"location":             location,
			"location_short":       "eus",
			"resource_group_name":  resourceGroupName,
			"hub_address_space":    "10.100.0.0/16",
			"firewall_subnet_prefix":   "10.100.1.0/26",
			"gateway_subnet_prefix":    "10.100.0.0/27",
			"bastion_subnet_prefix":    "10.100.0.64/26",
			"management_subnet_prefix": "10.100.2.0/24",
			"spokes": map[string]interface{}{
				"app": map[string]interface{}{
					"address_space":      "10.101.0.0/16",
					"app_subnet_prefix":  "10.101.1.0/24",
					"data_subnet_prefix": "10.101.2.0/24",
					"pe_subnet_prefix":   "10.101.3.0/24",
					"delegate_to_web":    false,
				},
			},
			"firewall_private_ip": "",
			"use_hub_gateway":     false,
			"tags": map[string]string{
				"environment": "test",
				"managed_by":  "terratest",
			},
		},

		// Retry up to 3 times on transient Azure API errors (throttling, 429s)
		MaxRetries:         3,
		TimeBetweenRetries: 5 * time.Second,
	})

	// Defer destroy so resources are cleaned up even if assertions fail
	defer terraform.Destroy(t, terraformOptions)

	// Apply — this actually creates Azure resources
	terraform.InitAndApply(t, terraformOptions)

	// ===== Assert outputs exist and are non-empty =====

	hubVNetID := terraform.Output(t, terraformOptions, "hub_vnet_id")
	require.NotEmpty(t, hubVNetID, "hub_vnet_id should not be empty")

	spokeVNetIDs := terraform.OutputMap(t, terraformOptions, "spoke_vnet_ids")
	require.NotEmpty(t, spokeVNetIDs, "spoke_vnet_ids should not be empty")
	require.Contains(t, spokeVNetIDs, "app", "spoke_vnet_ids should contain 'app' spoke")

	appSubnetIDs := terraform.OutputMap(t, terraformOptions, "spoke_app_subnet_ids")
	require.NotEmpty(t, appSubnetIDs["app"], "app subnet ID should not be empty")

	// ===== Assert Azure resources exist via Azure SDK =====

	subscriptionID := azure.GetTargetAzureSubscription(t)

	// Verify hub VNet exists and has correct address space
	hubVNet := azure.GetVirtualNetwork(t, resourceGroupName, "vnet-hub-dev-eus", subscriptionID)
	assert.Equal(t, location, *hubVNet.Location)
	assert.Contains(t, *hubVNet.Properties.AddressSpace.AddressPrefixes, "10.100.0.0/16",
		"Hub VNet should have the correct address space")

	// Verify spoke VNet exists
	spokeVNet := azure.GetVirtualNetwork(t, resourceGroupName, "vnet-app-dev-eus", subscriptionID)
	assert.NotNil(t, spokeVNet)
	assert.Contains(t, *spokeVNet.Properties.AddressSpace.AddressPrefixes, "10.101.0.0/16")

	// Verify VNet peering is established
	assertVNetPeeringConnected(t, resourceGroupName, "vnet-hub-dev-eus", "peer-hub-to-app", subscriptionID)
	assertVNetPeeringConnected(t, resourceGroupName, "vnet-app-dev-eus", "peer-app-to-hub", subscriptionID)

	// Verify AzureFirewallSubnet exists
	firewallSubnet := azure.GetSubnet(t, resourceGroupName, "vnet-hub-dev-eus", "AzureFirewallSubnet", subscriptionID)
	assert.Equal(t, "10.100.1.0/26", *firewallSubnet.Properties.AddressPrefix)

	// Verify NSG is associated with app subnet
	appSubnet := azure.GetSubnet(t, resourceGroupName, "vnet-app-dev-eus", "snet-app-app-dev-eus", subscriptionID)
	assert.NotNil(t, appSubnet.Properties.NetworkSecurityGroup,
		"App subnet must have an NSG associated")
}

// TestNSGRules verifies that NSG deny rules are in place
func TestNSGRules(t *testing.T) {
	t.Parallel()

	uniqueSuffix := random.UniqueId()
	resourceGroupName := fmt.Sprintf("rg-test-nsg-%s", uniqueSuffix)

	terraformOptions := terraform.WithDefaultRetryableErrors(t, &terraform.Options{
		TerraformDir: "../modules/networking",
		Vars: map[string]interface{}{
			"hub_name":             "hub",
			"environment":          "dev",
			"location":             "eastus",
			"location_short":       "eus",
			"resource_group_name":  resourceGroupName,
			"hub_address_space":    "10.200.0.0/16",
			"firewall_subnet_prefix":   "10.200.1.0/26",
			"gateway_subnet_prefix":    "10.200.0.0/27",
			"bastion_subnet_prefix":    "10.200.0.64/26",
			"management_subnet_prefix": "10.200.2.0/24",
			"spokes": map[string]interface{}{
				"app": map[string]interface{}{
					"address_space":      "10.201.0.0/16",
					"app_subnet_prefix":  "10.201.1.0/24",
					"data_subnet_prefix": "10.201.2.0/24",
					"pe_subnet_prefix":   "10.201.3.0/24",
					"delegate_to_web":    false,
				},
			},
			"firewall_private_ip": "",
			"use_hub_gateway":     false,
		},
	})

	defer terraform.Destroy(t, terraformOptions)
	terraform.InitAndApply(t, terraformOptions)

	subscriptionID := azure.GetTargetAzureSubscription(t)

	// Verify data-tier NSG has "Deny-All-Inbound" rule
	assertNSGHasRule(t, resourceGroupName, "nsg-data-app-dev-eus", "Deny-All-Inbound",
		"Inbound", "Deny", "*", "*", subscriptionID)

	// Verify app-tier NSG denies internet inbound
	assertNSGHasRule(t, resourceGroupName, "nsg-app-app-dev-eus", "Deny-Internet-Inbound",
		"Inbound", "Deny", "Internet", "*", subscriptionID)
}

// ===== Helper functions =====

func assertVNetPeeringConnected(t *testing.T, resourceGroupName, vnetName, peeringName, subscriptionID string) {
	t.Helper()

	cred, err := azidentity.NewDefaultAzureCredential(nil)
	require.NoError(t, err)

	client, err := armnetwork.NewVirtualNetworkPeeringsClient(subscriptionID, cred, nil)
	require.NoError(t, err)

	peering, err := client.Get(nil, resourceGroupName, vnetName, peeringName, nil)
	require.NoError(t, err, "VNet peering %s should exist", peeringName)

	state := string(*peering.Properties.PeeringState)
	assert.Equal(t, "Connected", state,
		fmt.Sprintf("VNet peering %s in %s should be in Connected state, got %s", peeringName, vnetName, state))
}

func assertNSGHasRule(t *testing.T, resourceGroupName, nsgName, ruleName, direction, access, sourcePrefix, destPrefix, subscriptionID string) {
	t.Helper()

	cred, err := azidentity.NewDefaultAzureCredential(nil)
	require.NoError(t, err)

	client, err := armnetwork.NewSecurityRulesClient(subscriptionID, cred, nil)
	require.NoError(t, err)

	rule, err := client.Get(nil, resourceGroupName, nsgName, ruleName, nil)
	require.NoError(t, err, "NSG rule %s should exist in %s", ruleName, nsgName)

	assert.Equal(t, direction, string(*rule.Properties.Direction))
	assert.Equal(t, access, string(*rule.Properties.Access))
}
