// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

contract MockERC20 {
    string public name = "Mock";
    string public symbol = "MOCK";
    uint8 public constant decimals = 18;
    uint256 public totalSupply;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;
    bool public fail;
    bool public noReturn;

    function setNoReturn(bool value) external {
        noReturn = value;
    }
    address public callback;
    bytes public callbackData;
    bool public reentered;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
        totalSupply += amount;
    }

    function configure(bool fail_, address callback_, bytes calldata data) external {
        fail = fail_;
        callback = callback_;
        callbackData = data;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        return _transfer(msg.sender, to, amount);
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        return _transfer(from, to, amount);
    }

    function _transfer(address from, address to, uint256 amount) internal returns (bool) {
        if (fail) return false;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        if (callback != address(0)) {
            address target = callback;
            callback = address(0);
            (reentered,) = target.call(callbackData);
        }
        if (noReturn) {
            assembly ("memory-safe") { return(0, 0) }
        }
        return true;
    }
}
