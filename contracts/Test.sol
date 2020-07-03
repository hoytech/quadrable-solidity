pragma solidity ^0.6.0;

import "./Quadrable.sol";

contract Test {
    constructor() public {
        bytes32 root = Quadrable.importProof(hex"0000013ac225168df54212a25c1c01fd35bebfea408fdac2e31ddd6f80a4bbf9a5f1cb01620f60e2ba9c7804ddaad28e769649f0cfd71246f0ab6d1d56fd8622a7798f42a96c6f");
    }
}
