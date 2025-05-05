// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

// import "hardhat/console.sol";

import {IERC721, IERC721Errors} from "../interfaces/IERC721.sol"; 
import {Strings} from "../libraries/Strings.sol"; 
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol"; 
import {LibStakingToken, StakingTokenStorage} from "../libraries/LibStakingToken.sol";  
import {LibDiamond} from "../diamond/libraries/LibDiamond.sol";


contract StakingTokenFacet is IERC721, IERC721Errors {
  string internal constant NftName = "GLTR Staking Token";  
  string internal constant NftSymbol = "GST";
    
  function supportsInterface(bytes4 _interfaceID) external pure returns (bool) {
    return _interfaceID == 0x01ffc9a7  //ERC165
      || _interfaceID == 0x80ac58cd  //ERC721
      || _interfaceID == 0x5b5e139f;  //ERC721Metadata
  }

  

  /// @notice A descriptive name for a collection of NFTs in this contract
  function name() external pure returns (string memory name_) {
    return NftName;
  }

  /// @notice An abbreviated name for NFTs in this contract
  function symbol() external pure returns (string memory symbol_) {
    return NftSymbol;
  }

  function setTokenBaseURI(string calldata _url) external {
    LibDiamond.enforceIsContractOwner();
    LibStakingToken.diamondStorage().baseNFTURI = _url;
  }

  function ownerExistsAndReturnIt(uint256 _tokenId) internal view returns (address) {
    address owner = LibStakingToken.diamondStorage().tokenInfo[_tokenId].owner;
    if (owner == address(0)) {
        revert ERC721NonexistentToken(_tokenId);
    }
    return owner;
  }

  /// @notice A distinct Uniform Resource Identifier (URI) for a given asset.
  /// @dev Throws if `_tokenId` is not a valid NFT. URIs are defined in RFC
  ///  3986. The URI may point to a JSON file that conforms to the "ERC721
  ///  Metadata JSON Schema".
  function tokenURI(uint256 _tokenId) external view returns (string memory) {
     ownerExistsAndReturnIt(_tokenId);
     return string.concat(LibStakingToken.diamondStorage().baseNFTURI, Strings.toString(_tokenId));
  }

  /**
    * @dev Returns the number of tokens in ``owner``'s account.
    */
  function balanceOf(address _owner) external view returns (uint256 balance_) {
    if (_owner == address(0)) {
      revert ERC721InvalidOwner(address(0));
    }
    return LibStakingToken.diamondStorage().ownerTokenIds[_owner].length;
  }

  /**
    * @dev Returns the owner of the `tokenId` token.
    *
    * Requirements:
    *
    * - `tokenId` must exist.
    */
  function ownerOf(uint256 _tokenId) external view returns (address owner_){
    return ownerExistsAndReturnIt(_tokenId);
  }



  /**
    * @dev Safely transfers `tokenId` token from `from` to `to`.
    *
    * Requirements:
    *
    * - `from` cannot be the zero address.
    * - `to` cannot be the zero address.
    * - `tokenId` token must exist and be owned by `from`.
    * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
    * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon
    *   a safe transfer.
    *
    * Emits a {Transfer} event.
    */
  function safeTransferFrom(address _from, address _to, uint256 _tokenId, bytes calldata _data) external {
    internalTransferFrom(_from, _to, _tokenId);
    LibStakingToken.checkOnERC721Received(_from, _to, _tokenId, _data);
  }

  /**
    * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
    * are aware of the ERC-721 protocol to prevent tokens from being forever locked.
    *
    * Requirements:
    *
    * - `from` cannot be the zero address.
    * - `to` cannot be the zero address.
    * - `tokenId` token must exist and be owned by `from`.
    * - If the caller is not `from`, it must have been allowed to move this token by either {approve} or
    *   {setApprovalForAll}.
    * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon
    *   a safe transfer.
    *
    * Emits a {Transfer} event.
    */
  function safeTransferFrom(address _from, address _to, uint256 _tokenId) external {
    internalTransferFrom(_from, _to, _tokenId);
    LibStakingToken.checkOnERC721Received(_from, _to, _tokenId, ""); 
  }

  /**
    * @dev Transfers `tokenId` token from `from` to `to`.
    *
    * WARNING: Note that the caller is responsible to confirm that the recipient is capable of receiving ERC-721
    * or else they may be permanently lost. Usage of {safeTransferFrom} prevents loss, though the caller must
    * understand this adds an external call which potentially creates a reentrancy vulnerability.
    *
    * Requirements:
    *
    * - `from` cannot be the zero address.
    * - `to` cannot be the zero address.
    * - `tokenId` token must be owned by `from`.
    * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
    *
    * Emits a {Transfer} event.
    */
  function transferFrom(address _from, address _to, uint256 _tokenId) external {
    internalTransferFrom(_from, _to, _tokenId);
  }

  

  function internalTransferFrom(address _from, address _to, uint256 _tokenId) internal {
    if(_to == address(0)) {
      revert ERC721InvalidReceiver(address(0));
    }
    address owner = ownerExistsAndReturnIt(_tokenId);
    if(owner != _from) {
      revert ERC721IncorrectOwner(_from, _tokenId, owner);
    }
    if(!LibStakingToken.isAuthorized(owner, msg.sender, _tokenId)) {
       revert ERC721InsufficientApproval(msg.sender, _tokenId);
    }
    StakingTokenStorage storage st = LibStakingToken.diamondStorage();
    uint256 lastIndex = st.ownerTokenIds[owner].length - 1;
    uint256 currentIndex = st.tokenInfo[_tokenId].ownerTokenIdsIndex;
    if(lastIndex != currentIndex) {      
      uint256 lastTokenId = st.ownerTokenIds[owner][lastIndex];
      st.ownerTokenIds[owner][currentIndex] = lastTokenId;
      st.tokenInfo[lastTokenId].ownerTokenIdsIndex = currentIndex;
    }
    st.ownerTokenIds[owner].pop();

    st.tokenInfo[_tokenId].approved = address(0);
    st.tokenInfo[_tokenId].owner = _to;
    st.tokenInfo[_tokenId].ownerTokenIdsIndex = st.ownerTokenIds[_to].length;
    st.ownerTokenIds[_to].push(_tokenId);

    emit Transfer(_from, _to, _tokenId);
  }



  /**
    * @dev Gives permission to `to` to transfer `tokenId` token to another account.
    * The approval is cleared when the token is transferred.
    *
    * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
    *
    * Requirements:
    *
    * - The caller must own the token or be an approved operator.
    * - `tokenId` must exist.
    *
    * Emits an {Approval} event.
    */
  function approve(address _to, uint256 _tokenId) external {
    address owner = ownerExistsAndReturnIt(_tokenId);
    StakingTokenStorage storage st = LibStakingToken.diamondStorage();
    if(msg.sender != owner && !st.operators[owner][msg.sender]) {
      revert ERC721InvalidApprover(msg.sender);
    }
    emit Approval(owner, _to, _tokenId);
  }

  /**
    * @dev Approve or remove `operator` as an operator for the caller.
    * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
    *
    * Requirements:
    *
    * - The `operator` cannot be the address zero.
    *
    * Emits an {ApprovalForAll} event.
    */
  function setApprovalForAll(address _operator, bool _approved) external {
    if(_operator == address(0)) {
      revert ERC721InvalidOperator(_operator);
    }
    StakingTokenStorage storage st = LibStakingToken.diamondStorage();
    st.operators[msg.sender][_operator] = _approved;
    emit ApprovalForAll(msg.sender, _operator, _approved);
  }

  /**
    * @dev Returns the account approved for `tokenId` token.
    *
    * Requirements:
    *
    * - `tokenId` must exist.
    */
  function getApproved(uint256 _tokenId) external view returns (address operator_) {
    ownerExistsAndReturnIt(_tokenId);
    return LibStakingToken.diamondStorage().tokenInfo[_tokenId].approved;
  }

  /**
    * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
    *
    * See {setApprovalForAll}
    */
  function isApprovedForAll(address _owner, address _operator) external view returns (bool) {
    return LibStakingToken.diamondStorage().operators[_owner][_operator];
  }

  /**
    * @dev An `owner`'s token query was out of bounds for `index`.
    *
    * NOTE: The owner being `address(0)` indicates a global out of bounds index.
    */
  error ERC721OutOfBoundsIndex(address owner, uint256 index);  

  /// @notice Enumerate NFTs assigned to an owner
  /// @dev Throws if `_index` >= `balanceOf(_owner)` or if
  ///  `_owner` is the zero address, representing invalid NFTs.
  /// @param _owner An address where we are interested in NFTs owned by them
  /// @param _index A counter less than `balanceOf(_owner)`
  /// @return The token identifier for the `_index`th NFT assigned to `_owner`,
  ///   (sort order not specified)
  function tokenOfOwnerByIndex(address _owner, uint256 _index) external view returns (uint256) {
    StakingTokenStorage storage st = LibStakingToken.diamondStorage();
    if(_index >= st.ownerTokenIds[_owner].length) {
      revert ERC721OutOfBoundsIndex(_owner, _index);
    }
    return st.ownerTokenIds[_owner][_index];
  }
}

