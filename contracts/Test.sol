pragma solidity ^0.6.0;

import "./Quadrable.sol";

contract Test {
    constructor() public {
    }

    function prove(bytes memory enc) public view returns (bytes32) {
        Quadrable.Proof memory tree = Quadrable.importProof(enc);
        return Quadrable.getRoot(tree);
    }
}
