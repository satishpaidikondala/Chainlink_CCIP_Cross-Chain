// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {IRouterClient} from "@chainlink/contracts-ccip/src/v0.8/ccip/interfaces/IRouterClient.sol";
import {Client} from "@chainlink/contracts-ccip/src/v0.8/ccip/libraries/Client.sol";
import {CCIPReceiver} from "@chainlink/contracts-ccip/src/v0.8/ccip/applications/CCIPReceiver.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721Receiver} from "@openzeppelin/contracts/token/ERC721/IERC721Receiver.sol";
import "./CrossChainNFT.sol";

contract CCIPNFTBridge is CCIPReceiver, IERC721Receiver {
    // Contract dependencies
    CrossChainNFT public immutable nft;
    IRouterClient public router;
    IERC20 public linkToken;

    mapping(uint64 => address) public destinationBridges;

    // Events
    event NFTSent(
        bytes32 messageId,
        uint64 destinationChainSelector,
        address receiver,
        uint256 tokenId,
        string tokenURI
    );

    constructor(
        address _router,
        address _link,
        address _nft
    ) CCIPReceiver(_router) {
        router = IRouterClient(_router);
        linkToken = IERC20(_link);
        nft = CrossChainNFT(_nft);
    }

    function setDestinationBridge(uint64 chainSelector, address bridgeAddr) external {
        destinationBridges[chainSelector] = bridgeAddr;
    }

    // Main function to initiate the NFT transfer
    function sendNFT(
        uint64 destinationChainSelector,
        address receiver,
        uint256 tokenId
    ) external returns (bytes32 messageId) {
        require(nft.ownerOf(tokenId) == msg.sender, "Caller is not token owner");

        string memory tokenURI = nft.tokenURI(tokenId);
        nft.burn(tokenId); // Burn the token on this chain

        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            destinationBridges[destinationChainSelector],
            receiver,
            tokenId,
            tokenURI
        );

        // Get the fee required to send the CCIP message
        uint256 fees = router.getFee(destinationChainSelector, evm2AnyMessage);
        
        require(linkToken.balanceOf(address(this)) >= fees, "Not enough LINK to pay fees");

        linkToken.approve(address(router), fees);

        // Send the message via the CCIP router
        messageId = router.ccipSend(destinationChainSelector, evm2AnyMessage);

        emit NFTSent(
            messageId,
            destinationChainSelector,
            receiver,
            tokenId,
            tokenURI
        );

        return messageId;
    }

    // Callback function to receive messages from CCIP Router
    function _ccipReceive(Client.Any2EVMMessage memory message) internal override {
        // Decode the extra args
        (address receiver, uint256 tokenId, string memory tokenURI) = abi.decode(
            message.data,
            (address, uint256, string)
        );

        // Required idempotency check
        try nft.ownerOf(tokenId) returns (address) {
            // If token exists, don't mint again
            return;
        } catch {
             // Reverted with non existent token, safe to mint
            nft.mint(receiver, tokenId, tokenURI);
        }
    }

    // Estimate transfer cost in LINK tokens
    function estimateTransferCost(
        uint64 destinationChainSelector
    ) external view returns (uint256) {
        Client.EVM2AnyMessage memory evm2AnyMessage = _buildCCIPMessage(
            destinationBridges[destinationChainSelector],
            address(0), // Dummy values for estimation
            0,
            ""
        );

        return router.getFee(destinationChainSelector, evm2AnyMessage);
    }

    function _buildCCIPMessage(
        address _receiverBridge,
        address _nftReceiver,
        uint256 _tokenId,
        string memory _tokenURI
    ) internal pure returns (Client.EVM2AnyMessage memory) {
        // Encode the payload with receiver and tokenId and URI
        bytes memory payload = abi.encode(_nftReceiver, _tokenId, _tokenURI);

        Client.EVM2AnyMessage memory evm2AnyMessage = Client.EVM2AnyMessage({
            receiver: abi.encode(_receiverBridge), 
            data: payload, // ABI encoded receiver, tokenId and URI
            tokenAmounts: new Client.EVMTokenAmount[](0), // Empty array as no tokens are transferred
            extraArgs: Client._argsToBytes(
                // Minimum limit of 200,000 extra gas limit required
                Client.EVMExtraArgsV1({gasLimit: 800_000}) 
            ),
            feeToken: address(0) // address(0) to use native token or use LINK token address
        });

        // Use LINK token for fees
        return evm2AnyMessage;
    }

    function updateFeeToken(address _link, Client.EVM2AnyMessage memory evm2AnyMessage) internal pure returns(Client.EVM2AnyMessage memory) {
         evm2AnyMessage.feeToken = _link;
         return evm2AnyMessage;
    }


    // Required for safe NFT transfers to this contract
    function onERC721Received(
        address,
        address,
        uint256,
        bytes calldata
    ) external pure returns (bytes4) {
        return this.onERC721Received.selector;
    }
}
