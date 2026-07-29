// SPDX-License-Identifier: MIT

pragma solidity 0.8.31;

/// @dev Indicates a failure with an address, for example, `address(0)`.
error InvalidAddress();

/// @dev Indicates a failure with an amount. For example, `0`.
error InvalidAmount();

/// @dev Indicates a failure with an array's length. For example, `array.length() == 0`.
error InvalidArrayLength();

/// @dev Indicates a failure with an assignment. For example, `stateVariable == newVariable`.
error InvalidAssignment();

/// @dev Indicates a failure with a string. For example, `""`.
error InvalidString();
