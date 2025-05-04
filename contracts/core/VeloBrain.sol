// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

contract Proxy {
    // Storage for implementation contract address and admin
    address public implementation;
    address public admin;

    // Constructor to set the initial admin
    constructor(address _implementation) {
        admin = msg.sender;
        implementation = _implementation;
    }

    // Modifier to restrict functions to admin
    modifier onlyAdmin() {
        require(msg.sender == admin, "Not admin");
        _;
    }

    // Upgrade the implementation contract address
    function upgrade(address _newImplementation) external onlyAdmin {
        implementation = _newImplementation;
    }

    // Fallback function to delegate calls to the implementation
    fallback() external payable {
        address impl = implementation;
        require(impl != address(0), "Implementation not set");

        // Delegate call to the implementation contract
        (bool success, bytes memory data) = impl.delegatecall(msg.data);
        require(success, "Delegatecall failed");

        // Return data from delegatecall
        assembly {
            return(add(data, 0x20), mload(data))
        }
    }

    // Receive function to accept Ether (if needed)
    receive() external payable {}
}