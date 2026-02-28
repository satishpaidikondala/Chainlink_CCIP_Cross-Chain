// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract CrossChainNFT is ERC721, Ownable {
    address public bridge;
    mapping(uint256 => string) private _tokenURIs;

    constructor(
        string memory name,
        string memory symbol,
        address initialOwner
    ) ERC721(name, symbol) Ownable(initialOwner) {}

    // Modifier to allow only the bridge to call a function
    modifier onlyBridge() {
        require(msg.sender == bridge, "Caller is not the bridge");
        _;
    }

    // Function to set the bridge address
    function setBridge(address _bridge) external onlyOwner {
        bridge = _bridge;
    }

    function _setTokenURI(uint256 tokenId, string memory _tokenURI) internal virtual {
        require(_ownerOf(tokenId) != address(0), "ERC721Metadata: URI set of nonexistent token");
        _tokenURIs[tokenId] = _tokenURI;
    }

    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_ownerOf(tokenId) != address(0), "ERC721Metadata: URI query for nonexistent token");
        
        string memory _tokenURI = _tokenURIs[tokenId];
        return _tokenURI;
    }

    // Mint a new NFT with a specific token URI. Only callable by the bridge.
    // Includes idempotency check.
    function mint(
        address to,
        uint256 tokenId,
        string memory _tokenURI
    ) external onlyBridge {
        require(_ownerOf(tokenId) == address(0), "Token already exists");
        _safeMint(to, tokenId);
        _setTokenURI(tokenId, _tokenURI);
    }

    // Burn an existing NFT.
    function burn(uint256 tokenId) external {
        address owner = _ownerOf(tokenId);
        require(owner != address(0), "Token does not exist");
        
        // This is safe because _isAuthorized is the standard way in OZ v5 to check
        require(
            _msgSender() == owner || getApproved(tokenId) == _msgSender() || isApprovedForAll(owner, _msgSender()),
            "ERC721: caller is not token owner or approved"
        );
        _burn(tokenId);
    }
}
