pragma solidity ^0.6.0;
pragma experimental ABIEncoderV2;

import "./Quadrable.sol";

contract Test {
    function testProof(bytes memory encodedProof, bytes[] memory queries, bytes[] memory updateKeys, bytes[] memory updateVals) public view
                 returns (bytes32 origRoot, bytes[] memory queryResults, bytes32 updatedRoot) {
        uint256 rootNodeAddr = Quadrable.importProof(encodedProof);

        origRoot = Quadrable.getRoot(rootNodeAddr);


        queryResults = new bytes[](queries.length);

        for (uint256 i = 0; i < queries.length; i++) {
            // For test purposes, use empty string as "not found" sentinel
            (bool found, bytes memory res) = Quadrable.get(rootNodeAddr, keccak256(abi.encodePacked(queries[i])));

            if (found) require(res.length != 0, "unexpected empty string when record found (test problem)");
            else require(res.length == 0, "unexpected non-empty string when record not found (code problem)");

            queryResults[i] = res;
        }


        require(updateKeys.length == updateVals.length, "parallel update arrays size mismatch");

        for (uint i = 0; i < updateKeys.length; i++) {
            rootNodeAddr = Quadrable.put(rootNodeAddr, keccak256(abi.encodePacked(updateKeys[i])), updateVals[i]);
        }


        updatedRoot = Quadrable.getRoot(rootNodeAddr);
    }
}
