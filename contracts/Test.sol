pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./Quadrable.sol";

contract Test {
    function testProof(bytes memory encodedProof, bytes[] memory queries, bytes[] memory updateKeys, bytes[] memory updateVals) public view
                 returns (bytes32 origRoot, bytes[] memory queryResults, bytes32 updatedRoot) {
        Quadrable.Proof memory proof = Quadrable.importProof(encodedProof);

        origRoot = Quadrable.getRootHash(proof);


        queryResults = new bytes[](queries.length);

        for (uint256 i = 0; i < queries.length; i++) {
            // For test purposes, use empty string as "not found"
            (, bytes memory res) = Quadrable.get(proof, keccak256(abi.encodePacked(queries[i])));
            queryResults[i] = res;
        }


        require(updateKeys.length == updateVals.length, "parallel update arrays size mismatch");

        for (uint i = 0; i < updateKeys.length; i++) {
            Quadrable.put(proof, keccak256(abi.encodePacked(updateKeys[i])), updateVals[i]);
        }


        updatedRoot = Quadrable.getRootHash(proof);
    }
}
