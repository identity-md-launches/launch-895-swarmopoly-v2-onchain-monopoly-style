// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

/// @dev ABI-compatible subset of Uniswap v4-core 1.0.2. Currency and IHooks encode as address.
struct PoolKey {
    address currency0;
    address currency1;
    uint24 fee;
    int24 tickSpacing;
    address hooks;
}

struct SwapParams {
    bool zeroForOne;
    int256 amountSpecified;
    uint160 sqrtPriceLimitX96;
}

interface IPoolManager {
    function unlock(bytes calldata data) external returns (bytes memory);
    function swap(PoolKey calldata key, SwapParams calldata params, bytes calldata hookData) external returns (int256);
    function sync(address currency) external;
    function settle() external payable returns (uint256);
    function take(address currency, address to, uint256 amount) external;
}

interface IUnlockCallback {
    function unlockCallback(bytes calldata data) external returns (bytes memory);
}

interface IBoundGame {
    function currency() external view returns (address);
    function vault() external view returns (address);
    function pot() external view returns (address);
}
