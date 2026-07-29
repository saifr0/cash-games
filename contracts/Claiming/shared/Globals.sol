// SPDX-License-Identifier: MIT

pragma solidity 0.8.31;

/* ========================== FREE FUNCTIONS ========================== */

/**
 * @dev For more efficient reverts.
 */
function _revert(bytes4 errorSelector) pure {
    assembly {
        mstore(0x00, errorSelector)
        revert(0x00, 0x04)
    }
}
