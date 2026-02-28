# Cross-Chain NFT Transfer via Chainlink CCIP

This project implements a production-ready cross-chain NFT bridge using Chainlink CCIP, Foundry, and Docker.

## Setup Instructions

1. **Environment Variables**: Create an `.env` file based on `.env.example` and populate it with your testnet private key and the relevant RPC URLs.
2. **Containerization**: Use `docker-compose up -d --build` to launch the CLI environment. Use the command below to access the container bash to run commands:
   ```bash
   docker exec -it ccip-nft-bridge-cli /bin/sh
   ```

## Smart Contracts
- `CrossChainNFT.sol`: Represents an ERC721 token that allows minting governed conditionally by the bridge.
- `CCIPNFTBridge.sol`: Extends CCIPReceiver and interacts with the CCIP router to transfer tokens and data across chains.

## Local Test NFT
* The pre-minted **Test NFT TokenId** on Avalanche Fuji is: `1`

## CLI Tool
The cli tool uses ethers.js to initiate the transfer command out of the source chain to the destination blockchain:
```bash
npm run transfer -- --tokenId=1 --from=avalanche-fuji --to=arbitrum-sepolia --receiver=YOUR_WALLET_ADDRESS
```