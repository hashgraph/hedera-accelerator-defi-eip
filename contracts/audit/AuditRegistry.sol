// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.24;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC721/IERC721.sol";

/**
 * @title AuditRegistry
 * @author
 * @notice This contract manages audit records for building NFTs.
 */
contract AuditRegistry is AccessControl {
    bytes32 public constant AUDITOR_ROLE = keccak256("AUDITOR_ROLE");

    struct AuditRecord {
        uint256 buildingId;   // ID of the building NFT
        address auditor;      // Address of the auditor
        string ipfsHash;      // IPFS hash of the audit document
        uint256 timestamp;    // Timestamp when the audit was added
        bool revoked;         // Status of the audit record
    }

    mapping(uint256 => AuditRecord) public auditRecords;
    mapping(uint256 => uint256[]) public buildingAuditRecords;
    uint256 public auditRecordCounter = 0;
    IERC721 public buildingNFT;

    event AuditRecordAdded(
        uint256 indexed auditRecordId,
        uint256 indexed buildingId,
        address indexed auditor,
        string ipfsHash,
        uint256 timestamp
    );
    event AuditRecordUpdated(
        uint256 indexed auditRecordId,
        string newIpfsHash,
        uint256 timestamp
    );
    event AuditRecordRevoked(
        uint256 indexed auditRecordId,
        uint256 timestamp
    );
    event AuditorAdded(address indexed auditor);
    event AuditorRemoved(address indexed auditor);

    /**
     * @dev Constructor sets the IERC721 contract address and grants admin role.
     * @param _buildingNFTAddress Address of the IERC721 contract
     */
    constructor(address _buildingNFTAddress) {
        require(_buildingNFTAddress != address(0), "Invalid NFT contract address");
        buildingNFT = IERC721(_buildingNFTAddress);
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender); // Use internal function to assign admin role
    }

    modifier buildingExists(uint256 _buildingId) {
        require(_exists(_buildingId), "AuditRegistry: Building does not exist");
        _;
    }

    function _exists(uint256 tokenId) internal view returns (bool) {
        return buildingNFT.ownerOf(tokenId) != address(0);
    }

    function addAuditor(address _auditor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_auditor != address(0), "AuditRegistry: Invalid auditor address");
        grantRole(AUDITOR_ROLE, _auditor);
        emit AuditorAdded(_auditor);
    }

    function removeAuditor(address _auditor) external onlyRole(DEFAULT_ADMIN_ROLE) {
        revokeRole(AUDITOR_ROLE, _auditor);
        emit AuditorRemoved(_auditor);
    }

    /**
     * @notice Adds a new audit record for a building.
     * @param _buildingId The ID of the building NFT.
     * @param _ipfsHash The IPFS hash of the audit document.
     */
    function addAuditRecord(uint256 _buildingId, string calldata _ipfsHash)
        external
        onlyRole(AUDITOR_ROLE)
        buildingExists(_buildingId)
    {
        require(bytes(_ipfsHash).length > 0, "AuditRegistry: IPFS hash is required");

        auditRecordCounter++;
        auditRecords[auditRecordCounter] = AuditRecord({
            buildingId: _buildingId,
            auditor: msg.sender,
            ipfsHash: _ipfsHash,
            timestamp: block.timestamp,
            revoked: false
        });
        buildingAuditRecords[_buildingId].push(auditRecordCounter);

        emit AuditRecordAdded(
            auditRecordCounter,
            _buildingId,
            msg.sender,
            _ipfsHash,
            block.timestamp
        );
    }

    /**
     * @notice Updates an existing audit record.
     * @param _auditRecordId The ID of the audit record to update.
     * @param _newIpfsHash The new IPFS hash of the audit document.
     */
    function updateAuditRecord(uint256 _auditRecordId, string calldata _newIpfsHash)
        external
        onlyRole(AUDITOR_ROLE)
    {
        require(bytes(_newIpfsHash).length > 0, "AuditRegistry: IPFS hash is required");
        AuditRecord storage record = auditRecords[_auditRecordId];
        require(record.auditor == msg.sender, "AuditRegistry: Not the original auditor");
        require(!record.revoked, "AuditRegistry: Cannot update a revoked record");

        record.ipfsHash = _newIpfsHash;
        record.timestamp = block.timestamp;

        emit AuditRecordUpdated(_auditRecordId, _newIpfsHash, block.timestamp);
    }

    /**
     * @notice Revokes an audit record.
     * @param _auditRecordId The ID of the audit record to revoke.
     */
    function revokeAuditRecord(uint256 _auditRecordId) external onlyRole(AUDITOR_ROLE) {
        AuditRecord storage record = auditRecords[_auditRecordId];
        require(record.auditor == msg.sender, "AuditRegistry: Not the original auditor");
        require(!record.revoked, "AuditRegistry: Record already revoked");

        record.revoked = true;

        emit AuditRecordRevoked(_auditRecordId, block.timestamp);
    }

    /**
     * @notice Retrieves audit records for a specific building.
     * @param _buildingId The ID of the building NFT.
     * @return An array of audit record IDs.
     */
    function getAuditRecordsByBuilding(uint256 _buildingId)
        external
        view
        returns (uint256[] memory)
    {
        return buildingAuditRecords[_buildingId];
    }

    /**
     * @notice Retrieves details of a specific audit record.
     * @param _auditRecordId The ID of the audit record.
     * @return The AuditRecord struct containing audit details.
     */
    function getAuditRecordDetails(uint256 _auditRecordId)
        external
        view
        returns (AuditRecord memory)
    {
        return auditRecords[_auditRecordId];
    }
}
