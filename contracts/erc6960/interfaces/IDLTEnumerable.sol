// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./IDLT.sol";

/**
 * @title DLT Standard, optional enumeration extension
 */
interface IDLTEnumerable is IDLT {
    /**
     * @dev Returns the total number of main ids.
     */
    function totalMainIds() external view returns (uint256);

    /**
     * @dev Returns the total number of sub ids for each main Ids.
     */
    function totalSubIds(int64 mainId) external view returns (uint256);

    /**
     * @dev Returns the total supply of main ids.
     */
    function totalMainSupply(int64 mainId) external view returns (uint256);

    /**
     * @dev Returns the total supply of sub ids for each main Ids.
     */
    function totalSubSupply(
        int64 mainId,
        int64 subId
    ) external view returns (uint256);

    /**
     * @dev Returns array of all sub ids for a main id
     */
    function getSubIds(int64 mainId) external view returns (int64[] memory);

    /**
     * @dev Returns total sub id balance of owner for each main id
     */
    function subIdBalanceOf(
        address owner,
        int64 mainId
    ) external view returns (uint256);
}
