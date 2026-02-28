// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Script.sol";
import "../src/CrossChainNFT.sol";
import "../src/CCIPNFTBridge.sol";

contract Deploy is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        
        vm.startBroadcast(deployerPrivateKey);

        // Deploy to Fuji (Requires running with Fuji RPC)
        if (block.chainid == 43113) {
            address router = vm.envAddress("CCIP_ROUTER_FUJI");
            address link = vm.envAddress("LINK_TOKEN_FUJI");

            CrossChainNFT nft = new CrossChainNFT("CrossChainNFT", "CCNFT", vm.addr(deployerPrivateKey));
            CCIPNFTBridge bridge = new CCIPNFTBridge(router, link, address(nft));
            nft.setBridge(address(bridge));
            
            // Pre-mint NFT ID 1 to the deployer for testing
            nft.mint(vm.addr(deployerPrivateKey), 1, "https://example.com/nft/1");
            
            console.log("Fuji NFT deployed to:", address(nft));
            console.log("Fuji Bridge deployed to:", address(bridge));
        }

        // Deploy to Arbitrum Sepolia (Requires running with Arbi RPC)
        if (block.chainid == 421614) {
            address router = vm.envAddress("CCIP_ROUTER_ARBITRUM_SEPOLIA");
            // NOTE: Add LINK_TOKEN_ARBITRUM_SEPOLIA to env if needed. For now we use the testnet link address.
            address link = 0xb1D4538B4571d411F07960EF2838Ce337FE1E80E;

            CrossChainNFT nft = new CrossChainNFT("CrossChainNFT", "CCNFT", vm.addr(deployerPrivateKey));
            CCIPNFTBridge bridge = new CCIPNFTBridge(router, link, address(nft));
            nft.setBridge(address(bridge));

            console.log("Arbitrum Sepolia NFT deployed to:", address(nft));
            console.log("Arbitrum Sepolia Bridge deployed to:", address(bridge));
        }

        vm.stopBroadcast();
    }
}
