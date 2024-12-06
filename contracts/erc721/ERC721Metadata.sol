// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC721/ERC721.sol";
import "@openzeppelin/contracts/token/ERC721/extensions/ERC721URIStorage.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/utils/Strings.sol";

/**
 * @title ERC721Metadata
 * @author Hashgraph
 * @notice ERC721 custom contract to handle onchain metadata
 */
contract ERC721Metadata is IERC721Metadata, ERC721, ERC721URIStorage, Ownable {
    using Strings for string;

    /**
     * @dev nextTokenId used to autogenerate token ids
     */
    uint256 private nextTokenId;

    /**
     * @dev metadata tokenId/key hash map to store token metadata
     */
    mapping(bytes32 => KeyValue) internal metadata;

    /**
     * @dev metadataIndex key/value hash map to perform gas optmized metadata based filtering
     */
    mapping(bytes32 => uint256[]) private metadataIndex;

    /**
     * @dev metadataKeys tokenId map to store a list of included keys for gas optmized metadata based filtering
     */
    mapping(uint256 => string[]) internal metadataKeys;

    /**
     * @dev isFrozen boolean flag to check if token metadata is frozen
     */
    mapping(uint256 => bool) internal isFrozen;

    /**
     * @dev collectionMetadata map to store collection metadata
     */
    mapping(string => KeyValue) internal collectionMetadata;

    /**
     * @dev collectionMetadataKeys list of included keys for gas optmized metadata based filtering
     */
    string[] internal collectionMetadataKeys;

    struct KeyValue {
        string key;
        string value;
        bool exists;
    }

    struct TokenDetails {
        uint256 id;
        string uri;
        address owner;
        KeyValue[] metadata;
    }

    modifier onlyTokenOwner(uint256 _tokenId) {
        require(ownerOf(_tokenId) == _msgSender(), "ERC721Metadata: not token owner");
        _;
    }

    modifier whenUnfrozen(uint256 _tokenId) {
        require(!isFrozen[_tokenId], "ERC721Metadata: token metadata can no longer be modified");
        _;
    }

    /**
     * Contructor
     * @param _name Token Name
     * @param _symbol Token Symbol
     */
    constructor (string memory _name, string memory _symbol) 
        ERC721(_name, _symbol) 
        Ownable(_msgSender()) {}

    // view calls
    /**
     * .getMetadata(uint256) get metadata list  of a given token
     * @param _tokenId uint256 NFT id
     * @return KeyValue[] list of metadata key/value pairs
     */
    function getMetadata(uint256 _tokenId) public view returns(KeyValue[] memory) {
        KeyValue[] memory data = new KeyValue[](metadataKeys[_tokenId].length);

        for (uint i = 0; i < metadataKeys[_tokenId].length; i++) {
            string memory key = metadataKeys[_tokenId][i];
            data[i] = getMetadata(_tokenId, key);
        }

        return data;
    }

    /**
     * .getMetadata(uint256,string) get single metada by token Id and key
     * @param _tokenId uint256 NFT id
     * @param _key string key to 
     * @return KeyValue metadata
     */
    function getMetadata(uint256 _tokenId, string memory _key) public view returns(KeyValue memory) {
        return metadata[_tokenIdKeyHash(_tokenId,_key)];
    }

    /**
     * .getCollectionMetadata() return collection metadata list
     * @return KeyValue[] metadata lists
     */
    function getCollectionMetadata() external view returns(KeyValue[] memory) {
        KeyValue[] memory data = new KeyValue[](collectionMetadataKeys.length);

        for (uint i = 0; i < collectionMetadataKeys.length; i++) {
            string memory key = collectionMetadataKeys[i];
            data[i] = (collectionMetadata[key]);
        }

        return data;
    }

    /**
     * .getCollectionMetadata(string) return collection metadata
     * @param _key key string
     * @return KeyValue metadata
     */
    function getCollectionMetadata(string memory _key) external view returns(KeyValue memory) {
        return collectionMetadata[_key];
    }

    /**
     * .filterTokens(string, string) filter tokens that have the given key/value metadata pair
     * @param _key string key to filter 
     * @param _value  string value to filter
     * @return TokenDetails[] list of filtered tokens 
     */
    function filterTokens(string memory _key, string memory _value) external view returns(TokenDetails[] memory) {
        uint256[] memory _tokensIds = metadataIndex[_keyValueHash(_key, _value)];
        return _getTokenDetails(_tokensIds);
    }

    /**
     * .filterTokens(string[], string[]) filter tokens that have all the given key/value metadata pairs
     * @param _keys string[] list of keys to filter 
     * @param _values  string[] list of values to filter
     * @return TokenDetails[] list of filtered tokens 
     */
    function filterTokens(string[] memory _keys, string[] memory _values)
        external
        view
        returns (TokenDetails[] memory)
    {
        require(_keys.length == _values.length, "ERC721Metadata: keys and values length mismatch");

        // Retrieve the initial set of tokens for the first key-value pair
        uint256[] memory filteredTokens = metadataIndex[_keyValueHash(_keys[0], _values[0])];

        // Iteratively refine the list based on additional key-value pairs
        for (uint256 i = 1; i < _keys.length; i++) {
            uint256[] memory tokensForPair = metadataIndex[_keyValueHash(_keys[i], _values[i])];
            filteredTokens = _intersectArrays(filteredTokens, tokensForPair);
        }

        // Return the details of the filtered tokens
        return _getTokenDetails(filteredTokens);
    }


    // mutable calls
    /**
     * .setMetadata(uint256,string,string) upsert single metadata
     * @param _tokenId uint256 NFT id
     * @param _key string key
     * @param _newValue string value to be setted
     * @notice Only token owner can call this function
     * @notice Only when the token is unfrozen this function can be called
     */
    function setMetadata(uint256 _tokenId, string memory _key, string memory _newValue) 
        external 
        onlyTokenOwner(_tokenId) 
        whenUnfrozen(_tokenId) 
    {
        _setMetadata(_tokenId, _key, _newValue);
    }
    
    /**
     * .setMetadata(uint256,string,string) upsert multiple metadata
     * @param _tokenId uint256 NFT id
     * @param _keys string keys to include
     * @param _values string value to be setted
     * @notice Only token owner can call this function
     * @notice Only when the token is unfrozen this function can be called
     */
    function setMetadata(uint256 _tokenId, string[] memory _keys, string[] memory _values)
        external 
        onlyTokenOwner(_tokenId) 
        whenUnfrozen(_tokenId) 
    {
        _setMetadata(_tokenId, _keys, _values);
    }

    /**
     * .freezeMetadata(uint256) freeze metadata for a given token
     * @param _tokenId uint256 NFT id
     * @notice Only the contract owner can call this function
     * @notice Only when the token is unfrozen this function can be called
     */
    function freezeMetadata(uint256 _tokenId) external onlyOwner whenUnfrozen(_tokenId) {
        isFrozen[_tokenId] = true;
    }

    // mint functions
    /**
     * .mint(address,string) mint token
     * @param _to address to mint the address to
     * @param _uri string token URI
     * @notice only the contract owner can call this function
     */
    function mint(address _to, string memory _uri) external onlyOwner {
       _mint(_to, _uri);
    }

    /**
     * .mint(address, string, string[], string[]) mint token and set metadata
     * @param _to address to mint address to
     * @param _uri string token uri
     * @param _keys metadata keys
     * @param _values metadata values
     * @notice Only contract owner can call this function
     */
    function mint(address _to, string memory _uri, string[] memory _keys, string[] memory _values) 
        external 
        onlyOwner 
    {
       uint256 tokenId = _mint(_to, _uri);
       _setMetadata(tokenId, _keys, _values);
    }

    /**
     * .setTokenURI(uint256,string) set token URI
     * @param _tokenId uint256 NFT id
     * @param _newURI string token uri
     * @notice Only contract owner can call this function
     * @notice Only when the token is unfrozen this function can be called
     */
    function setTokenURI(uint256 _tokenId, string memory _newURI) external onlyOwner whenUnfrozen(_tokenId) {
        _setTokenURI(_tokenId, _newURI);
    }
    
    /**
     * .setCollectionMetadata(string[],string[]) sets collection metadata
     * @param _keys list of keys
     * @param _values list of values
     * @notice Only contract owner can call this function
     */
    function setCollectionMetadata(string[] memory _keys, string[] memory _values) external onlyOwner {
        _setCollectionMetadata(_keys, _values);
    }

    // internal functions
    function _mint(address _to, string memory _uri) internal returns(uint256 _tokenId) {
        _tokenId = nextTokenId++;
        _safeMint(_to, _tokenId);
        _setTokenURI(_tokenId, _uri);
    }

    function _setMetadata(uint256 _tokenId, string memory _key, string memory _newValue) internal {
        KeyValue memory data = KeyValue(_key, _newValue, true);

        if (!metadata[_tokenIdKeyHash(_tokenId, _key)].exists)
            metadataKeys[_tokenId].push(_key);

        metadata[_tokenIdKeyHash(_tokenId, _key)] = data;
        _updateIndex(_tokenId, _key, _newValue);
    }

    function _setMetadata(uint256 _tokenId, string[] memory _keys, string[] memory _values) internal {
        require(_keys.length == _values.length, "ERC721Metadata: array length mismatch");

        for (uint i = 0; i < _keys.length; i++) {       
            _setMetadata(_tokenId, _keys[i], _values[i]);
        }
    }

    function _setCollectionMetadata(string[] memory _keys, string[] memory _values) internal {
        require(_keys.length > 0, "ERC721Metadata: invalid array length");
        require(_keys.length == _values.length, "ERC721Metadata: array length mismatch");

        for (uint i = 0; i < _keys.length; i++) {       
             KeyValue memory data = KeyValue(_keys[i], _values[i], true);

            if (!collectionMetadata[_keys[i]].exists)
                collectionMetadataKeys.push(_keys[i]);

            collectionMetadata[_keys[i]] = data;
        }
    }

    function _getTokenDetails(uint256[] memory _ids) internal view returns (TokenDetails[] memory) {
        TokenDetails[] memory _details = new TokenDetails[](_ids.length);
        
        for (uint i = 0; i < _ids.length; i++) {
            _details[i] = _getTokenDetails(_ids[i]);
        }

        return _details;
    }

    function _getTokenDetails(uint256 _id) internal view returns (TokenDetails memory _details) {
        return TokenDetails(_id, tokenURI(_id), ownerOf(_id), getMetadata(_id));
    }

    function _resizeArray(uint256[] memory array, uint256 newSize) internal pure returns (uint256[] memory) {
        uint256[] memory resizedArray = new uint256[](newSize);
        for (uint256 i = 0; i < newSize; i++) {
            resizedArray[i] = array[i];
        }
        return resizedArray;
    }

    function _tokenIdKeyHash(uint256 _tokenId, string memory _key) internal pure returns(bytes32) {
        return keccak256(abi.encodePacked(_tokenId, _key));
    }

    function _keyValueHash(string memory _value, string memory _key) internal pure returns(bytes32) {
        return keccak256(abi.encodePacked(_value, _key));
    }

    function _updateIndex(uint256 tokenId, string memory key, string memory value) internal {
        uint256[] storage tokens = metadataIndex[_keyValueHash(key, value)];

        // Check if tokenId already exists in the index
        for (uint256 i = 0; i < tokens.length; i++) {
            if (tokens[i] == tokenId) {
                return; // Token already indexed, no need to re-add
            }
        }

        // Add tokenId to the index
        tokens.push(tokenId);
    }

    function _intersectArrays(uint256[] memory arr1, uint256[] memory arr2)
        internal
        pure
        returns (uint256[] memory)
    {
        // Use a memory mapping to track common elements
        uint256 maxLength = arr1.length > arr2.length ? arr2.length : arr1.length;
        uint256[] memory tempResult = new uint256[](maxLength);
        uint256 index = 0;

        for (uint256 i = 0; i < arr1.length; i++) {
            for (uint256 j = 0; j < arr2.length; j++) {
                if (arr1[i] == arr2[j]) {
                    tempResult[index++] = arr1[i];
                    break;
                }
            }
        }

        // Resize the array to match the actual number of common elements
        return _resizeArray(tempResult, index);
    }


    // The following functions are overrides required by Solidity.
    function tokenURI(uint256 tokenId)
        public
        view
        override(IERC721Metadata, ERC721, ERC721URIStorage)
        returns (string memory)
    {
        return super.tokenURI(tokenId);
    }

    function supportsInterface(bytes4 interfaceId)
        public
        view
        override(IERC165, ERC721, ERC721URIStorage)
        returns (bool)
    {
        return super.supportsInterface(interfaceId);
    }
}
