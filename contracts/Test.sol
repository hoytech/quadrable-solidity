pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./Quadrable.sol";

contract Test {
    constructor() public {
    }

    function prove(bytes memory encodedProof, bytes[] memory queries) public view returns (bytes32, bytes[] memory) {
        bytes[] memory results = new bytes[](queries.length);

        Quadrable.Proof memory proof = Quadrable.importProof(encodedProof);
        bytes32 rootHash = Quadrable.getRootHash(proof);

        for (uint256 i = 0; i < queries.length; i++) {
            (, bytes memory res) = Quadrable.get(proof, keccak256(abi.encodePacked(queries[i])));
            results[i] = res;
        }

        return (rootHash, results);
    }
}
