const fs = require('fs');
const path = require('path');
const { program } = require('commander');
const { ethers } = require('ethers');

program
  .option('--tokenId <number>', 'Token ID')
  .option('--from <string>', 'Source Chain (avalanche-fuji | arbitrum-sepolia)')
  .option('--to <string>', 'Destination Chain')
  .option('--receiver <string>', 'Receiver Address')
  .parse(process.argv);

const options = program.opts();

const CHAIN_IDS = {
  'avalanche-fuji': 14767482510784806043n,
  'arbitrum-sepolia': 3478487238524512106n
};

// Simplified ABI with what we just need from CCIPNFTBridge
const BridgeABI = [
  "function estimateTransferCost(uint64 destinationChainSelector) external view returns (uint256)",
  "function sendNFT(uint64 destinationChainSelector, address receiver, uint256 tokenId) external returns (bytes32 messageId)",
  "event NFTSent(bytes32 messageId, uint64 destinationChainSelector, address receiver, uint256 tokenId, string tokenURI)"
];

async function main() {
  if (!options.tokenId || !options.from || !options.to || !options.receiver) {
    console.error("Missing required arguments");
    process.exit(1);
  }

  const sourceChain = options.from;
  const destinationChain = options.to;
  const receiver = options.receiver;
  const tokenId = options.tokenId;

  // Paths
  const logsDir = path.join(__dirname, '..', 'logs');
  const dataDir = path.join(__dirname, '..', 'data');
  const logFile = path.join(logsDir, 'transfers.log');
  const dataFile = path.join(dataDir, 'nft_transfers.json');

  if (!fs.existsSync(logsDir)) fs.mkdirSync(logsDir, { recursive: true });
  if (!fs.existsSync(dataDir)) fs.mkdirSync(dataDir, { recursive: true });
  if (!fs.existsSync(dataFile)) fs.writeFileSync(dataFile, '[]');
  
  // Format log entry
  const logMessage = `[${new Date().toISOString()}] Initiating transfer of Token ID ${tokenId} from ${sourceChain} to ${destinationChain} for receiver ${receiver}\n`;
  fs.appendFileSync(logFile, logMessage);

  console.log(`Sending NFT ${tokenId} from ${sourceChain} to ${destinationChain}...`);

  try {
    const deploymentPath = path.join(__dirname, '..', 'deployment.json');
    if(!fs.existsSync(deploymentPath)) {
        throw new Error("No deployment.json found. Please ensure contracts are deployed.");
    }
    const deployment = JSON.parse(fs.readFileSync(deploymentPath, 'utf8'));

    // Network setup
    let networkKey = sourceChain === 'avalanche-fuji' ? 'avalancheFuji' : 'arbitrumSepolia';
    const bridgeAddress = deployment[networkKey].bridgeContractAddress;

    if (!bridgeAddress) {
      throw new Error(`Bridge address for ${sourceChain} not found in deployment.json`);
    }

    // Load environment variables manually
    require('dotenv').config({ path: path.join(__dirname, '..', '.env') });
    
    const rpcUrlKey = sourceChain === 'avalanche-fuji' ? 'FUJI_RPC_URL' : 'ARBITRUM_SEPOLIA_RPC_URL';
    const rpcUrl = process.env[rpcUrlKey];
    
    if(!rpcUrl) throw new Error(`Missing ${rpcUrlKey} in .env file`);
    if(!process.env.PRIVATE_KEY) throw new Error(`Missing PRIVATE_KEY in .env file`);

    const provider = new ethers.JsonRpcProvider(rpcUrl);
    const signer = new ethers.Wallet(process.env.PRIVATE_KEY, provider);

    console.log(`Using signer: ${signer.address}`);

    // Load bridge contract
    const bridge = new ethers.Contract(bridgeAddress, BridgeABI, signer);

    const destChainSelector = CHAIN_IDS[destinationChain];
    if (!destChainSelector) throw new Error("Invalid destination chain");

    console.log(`Estimating transfer cost...`);
    // Estimate cost
    const fee = await bridge.estimateTransferCost(destChainSelector);
    
    console.log(`Initiating sendNFT transaction...`);
    const tx = await bridge.sendNFT(
      destChainSelector,
      receiver,
      tokenId
    );

    console.log(`Transaction submitted: ${tx.hash}`);
    fs.appendFileSync(logFile, `[${new Date().toISOString()}] Transaction Hash: ${tx.hash}\n`);

    const receipt = await tx.wait();

    let messageId;
    for (const log of receipt.logs) {
      try {
        const parsedLog = bridge.interface.parseLog(log);
        if (parsedLog && parsedLog.name === "NFTSent") {
          messageId = parsedLog.args.messageId;
        }
      } catch (e) {
        // Log may not belong to bridge
      }
    }
    
    console.log(`NFTSent Event Emitted with Message ID: ${messageId}`);

    const crypto = require("crypto");
    const transferData = {
      transferId: messageId || crypto.randomUUID(),
      tokenId: tokenId.toString(),
      sourceChain,
      destinationChain,
      sender: signer.address,
      receiver,
      ccipMessageId: messageId,
      sourceTxHash: tx.hash,
      destinationTxHash: null,
      status: 'initiated',
      metadata: {
        name: `Cross Chain NFT #${tokenId}`,
        description: "A transferrable CCIP NFT.",
        image: ""
      },
      timestamp: new Date().toISOString()
    };

    const transfers = JSON.parse(fs.readFileSync(dataFile, 'utf8'));
    transfers.push(transferData);
    fs.writeFileSync(dataFile, JSON.stringify(transfers, null, 2));

    fs.appendFileSync(logFile, `[${new Date().toISOString()}] transfer successfully initiated.\n`);
    console.log("Transfer successful.");

  } catch (error) {
    console.error("Transfer failed:", error);
    fs.appendFileSync(logFile, `[${new Date().toISOString()}] Transfer failed: ${error.message}\n`);
    process.exit(1);
  }
}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});
