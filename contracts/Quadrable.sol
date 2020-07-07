pragma solidity ^0.6.0;

import "@nomiclabs/buidler/console.sol";

import "./BytesLib.sol";

library Quadrable {
    enum StrandType {
        Leaf, // = 0,
        WitnessLeaf, // = 1,
        WitnessEmpty, // = 2,
        Unused3,
        Unused4,
        Unused5,
        Unused6,
        Unused7,
        Unused8,
        Unused9,
        Unused10,
        Unused11,
        Unused12,
        Unused13,
        Unused14,
        Invalid // = 15,
    }

    enum NodeType { // Internal values (different from C++ implementation)
        Empty, // = 0
        Leaf, // = 1
        Witness, // = 2
        WitnessLeaf, // = 3
        Branch // = 4
    }

    struct Proof {
        bytes encoded;

        uint256 numStrands;
        uint256 strandStateAddr; // memory address where strand states start
        uint256 startOfCmds; // offset within encoded where cmds start
    }

    // Strand state (128 bytes):
    //     uint256: [0 padding...] [1 byte: depth] [1 byte: merged] [4 bytes: next] [4 bytes: nodeAddr]
    //     [32 bytes: keyHash]
    //     [64 bytes: possibly containing leaf node for this strand]

    // Node (64 bytes):
    //     uint256 nodeContents: [0 padding...] [nodeType specific (see below)] [1 byte: nodeType]
    //                Leaf: [4 bytes: encodedStrandOffset]
    //         WitnessLeaf: [4 bytes: encodedStrandOffset]
    //             Witness: unused
    //              Branch: [4 bytes: leftNodeAddr] [4 bytes: rightNodeAddr]
    //     bytes32 nodeHash

    function saveStrandState(Proof memory proof, uint256 strandIndex, uint256 newStrandState) private pure {
        uint256 strandStateAddr = proof.strandStateAddr;

        assembly {
            let addr := add(strandStateAddr, mul(strandIndex, 128)) // FIXME shift left
            mstore(addr, newStrandState)
        }
    }

    // FIXME: break-out separate function to get keyHash
    function getStrandState(Proof memory proof, uint256 strandIndex) private pure returns (uint256 strandState, bytes32 keyHash) {
        uint256 strandStateAddr = proof.strandStateAddr;

        assembly {
            let addr := add(strandStateAddr, mul(strandIndex, 128)) // FIXME shift left
            strandState := mload(addr)
            keyHash := mload(add(addr, 32))
        }
    }

    function packStrandState(uint256 depth, uint256 merged, uint256 next, uint256 nodeAddr) private pure returns (uint256 strandState) {
        strandState = (depth << (9*8)) |
                      (merged << (8*8)) |
                      (next << (4*8)) |
                      nodeAddr;
    }

    function unpackStrandState(uint256 strandState) private pure returns (uint256 depth, uint256 merged, uint256 next, uint256 nodeAddr) {
        depth = strandState >> (9*8);
        merged = (strandState >> (8*8)) & 0xFF;
        next = (strandState >> (4*8)) & 0xFFFFFFFF;
        nodeAddr = strandState & 0xFFFFFFFF;
    }

    function strandStateDepth(uint256 strandState) private pure returns (uint256) {
        return (strandState >> (9*8)) & 0xFF;
    }

    function strandStateNext(uint256 strandState) private pure returns (uint256) {
        return (strandState >> (4*8)) & 0xFFFFFFFF;
    }

    function strandStateNodeAddr(uint256 strandState) private pure returns (uint256) {
        return strandState & 0xFFFFFFFF;
    }

    function buildNodeWitness(bytes32 nodeHash) private pure returns (uint256 nodeAddr) {
        uint256 nodeContents = uint256(NodeType.Witness);

        assembly {
            nodeAddr := mload(0x40)

            mstore(nodeAddr, nodeContents)
            mstore(add(nodeAddr, 32), nodeHash)

            mstore(0x40, add(nodeAddr, 64))
        }
    }

    function buildNodeBranch(uint256 leftNodeAddr, uint256 rightNodeAddr) private pure returns (uint256 nodeAddr) {
        uint256 nodeContents = (leftNodeAddr << (5*8)) | (rightNodeAddr << (1*8)) | uint256(NodeType.Branch);

        assembly {
            nodeAddr := mload(0x40)

            mstore(nodeAddr, nodeContents)

            mstore(32, 0) // Sort of a hack: If the address 0x00 is cast as a nodeAddr, then this makes the nodeHash = 0x00...
            let leftNodeHash := mload(add(leftNodeAddr, 32))
            let rightNodeHash := mload(add(rightNodeAddr, 32))
            mstore(0, leftNodeHash)
            mstore(32, rightNodeHash)

            let nodeHash := keccak256(0, 64)
            mstore(add(nodeAddr, 32), nodeHash)

            mstore(0x40, add(nodeAddr, 64))
        }
    }

    function getNodeType(uint256 nodeAddr) private pure returns (NodeType nodeType) {
        if (nodeAddr == 0) return NodeType.Empty;

        assembly {
            nodeType := and(mload(nodeAddr), 0xFF)
        }
    }

    function getNodeHash(uint256 nodeAddr) private pure returns (bytes32 nodeHash) {
        if (nodeAddr == 0) return bytes32(uint256(0));

        assembly {
            nodeHash := mload(add(nodeAddr, 32))
        }
    }

    function getNodeBranchLeft(uint256 nodeAddr) private pure returns (uint256) {
        uint256 nodeContents;

        assembly {
            nodeContents := mload(nodeAddr)
        }

        return (nodeContents >> (1*8)) & 0xFFFFFFFF;
    }

    function getNodeBranchRight(uint256 nodeAddr) private pure returns (uint256) {
        uint256 nodeContents;

        assembly {
            nodeContents := mload(nodeAddr)
        }

        return nodeContents >> (5*8);
    }

    function getNodeLeafKeyHash(Proof memory proof, uint256 nodeAddr) private pure returns (bytes32 keyHash) {
        bytes memory encoded = proof.encoded;

        assembly {
            let nodeContents := mload(nodeAddr)
            let encodedStrandOffset := shr(mul(1, 8), nodeContents)
            keyHash := mload(add(add(add(encoded, 0x20), encodedStrandOffset), 2))
        }
    }


    function importProof(bytes memory encoded) internal view returns (Proof memory) {
        Proof memory proof;

        proof.encoded = encoded;

        _parseStrands(proof);
        _processCmds(proof);

        (uint256 strandState,) = getStrandState(proof, 0);
        (uint256 depth,, uint256 next,) = unpackStrandState(strandState); // FIXME: use individual getters
        require(next == proof.numStrands, "next linked list not empty");
        require(depth == 0, "strand depth not at root");

        return proof;
    }


    function getRootNodeAddr(Proof memory proof) internal view returns (uint256 nodeAddr) {
        (uint256 strandState,) = getStrandState(proof, 0);
        nodeAddr = strandStateNodeAddr(strandState);
    }

    function getRootHash(Proof memory proof) internal view returns (bytes32) {
        return getNodeHash(getRootNodeAddr(proof));
    }


    // This function must not call anything that allocates memory, since it builds a
    // contiguous array of strands starting from the initial free memory pointer.

    function _parseStrands(Proof memory proof) private pure {
        bytes memory encoded = proof.encoded;
        uint256 offset = 0; // into proof.encoded
        uint256 numStrands = 0;

        require(BytesLib.toUint8(encoded, offset++) == 0, "Only CompactNoKeys encoding supported");

        uint256 strandStateAddr;
        assembly {
            strandStateAddr := mload(0x40)
        }

        // Setup strand state and embedded leaf nodes

        while (true) {
            uint256 encodedStrandOffset = offset;
            StrandType strandType = StrandType(BytesLib.toUint8(encoded, offset++));
            if (strandType == StrandType.Invalid) break;

            uint8 depth = BytesLib.toUint8(encoded, offset++);
            bytes32 keyHash = BytesLib.toBytes32(encoded, offset);
            offset += 32;

            bytes32 valHash;

            if (strandType == StrandType.Leaf) {
                uint256 valLen = 0;
                uint8 b;
                do {
                    b = BytesLib.toUint8(encoded, offset++); 
                    valLen = (valLen << 7) | (b & 0x7F);
                } while ((b & 0x80) != 0);

                assembly { valHash := keccak256(add(add(encoded, 0x20), offset), valLen) }

                offset += valLen;
            } else if (strandType == StrandType.WitnessLeaf) {
                valHash = BytesLib.toBytes32(encoded, offset);
                offset += 32;
            }

            uint256 strandState = packStrandState(depth, 0, numStrands+1, 0);

            assembly {
                let strandStateMemOffset := add(mload(0x40), mul(128, numStrands)) // FIXME shift left

                if iszero(eq(strandType, 2)) { // StrandType.WitnessEmpty
                    let nodeType := 1 // Default NodeType.Leaf
                    if eq(strandType, 1) { // ... unless StrandType.WitnessLeaf
                        nodeType := 3 // then NodeType.WitnessLeaf
                    }

                    let nodeContents := or(shl(8, encodedStrandOffset), nodeType)

                    mstore(0, keyHash)
                    mstore(32, valHash)
                    let nodeHash := keccak256(0, 65) // relies on most-significant byte of free space pointer being '\0'

                    mstore(add(strandStateMemOffset, 64), nodeContents)
                    mstore(add(strandStateMemOffset, 96), nodeHash)

                    strandState := or(strandState, add(strandStateMemOffset, 64)) // add the following nodeAddr to the strandState
                }

                mstore(strandStateMemOffset, strandState)
                mstore(add(strandStateMemOffset, 32), keyHash)
            }

            numStrands++;
        }

        // Bump free memory pointer over strand state we've just setup

        assembly {
            mstore(0x40, add(mload(0x40), mul(128, numStrands))) // FIXME shift left
        }

        // Output

        proof.numStrands = numStrands;
        proof.strandStateAddr = strandStateAddr;
        proof.startOfCmds = offset;
    }

    function _processCmds(Proof memory proof) private view {
        bytes memory encoded = proof.encoded;
        uint256 offset = proof.startOfCmds;

        uint256 currStrand = proof.numStrands - 1;

        while (offset < encoded.length) {
            uint8 cmd = BytesLib.toUint8(encoded, offset++);

            if ((cmd & 0x80) == 0) {
                (uint256 strandState, bytes32 keyHash) = getStrandState(proof, currStrand);
                (uint256 depth, uint256 merged, uint256 next, uint256 nodeAddr) = unpackStrandState(strandState);
                require(merged == 0, "can't operate on merged strand");

                if (cmd == 0) {
                    // merge

                    require(next != proof.numStrands, "no next strand");
                    (uint256 nextStrandState,) = getStrandState(proof, next);
                    require(depth == strandStateDepth(nextStrandState), "strands at different depths");

                    nodeAddr = buildNodeBranch(nodeAddr, strandStateNodeAddr(nextStrandState));

                    saveStrandState(proof, next, nextStrandState | (1 << (8*8))); // set merged in next strand

                    next = strandStateNext(nextStrandState);
                    depth--;
                } else {
                    // hashing

                    bool started = false;

                    for (uint i=0; i<7; i++) {
                        if (started) {
                            require(depth > 0, "can't hash depth below 0");

                            uint256 witnessNodeAddr;

                            if ((cmd & 1) != 0) {
                                // HashProvided
                                bytes32 witness = BytesLib.toBytes32(encoded, offset);
                                offset += 32;
                                witnessNodeAddr = buildNodeWitness(witness);
                            } else {
                                // HashEmpty
                                witnessNodeAddr = 0;
                            }

                            if ((uint256(keyHash) & (1 << (256 - depth))) == 0) {
                                nodeAddr = buildNodeBranch(nodeAddr, witnessNodeAddr);
                            } else {
                                nodeAddr = buildNodeBranch(witnessNodeAddr, nodeAddr);
                            }

                            depth--;
                        } else {
                            if ((cmd & 1) != 0) started = true;
                        }

                        cmd >>= 1;
                    }
                }

                uint256 newStrandState = packStrandState(depth, merged, next, nodeAddr);
                saveStrandState(proof, currStrand, newStrandState);
            } else {
                // jump
                uint256 action = cmd >> 5;
                uint256 distance = cmd & 0x1F;

                if (action == 4) { // short jump fwd
                    currStrand += distance + 1;
                } else if (action == 5) { // short jump rev
                    currStrand -= distance + 1;
                } else if (action == 6) { // long jump fwd
                    currStrand += 1 << (distance + 6);
                } else if (action == 7) { // long jump rev
                    currStrand -= 1 << (distance + 6);
                }

                require(currStrand < proof.numStrands, "jumped outside of proof strands");
            }
        }
    }

    function get(Proof memory proof, bytes32 keyHash) internal view returns (bool found, bytes memory) {
        uint256 nodeAddr = getRootNodeAddr(proof);
        uint256 depthMask = 1 << 255;
        NodeType nodeType;

        while(true) {
            nodeType = getNodeType(nodeAddr);

            if (nodeType == NodeType.Branch) {
                if ((uint256(keyHash) & depthMask) == 0) {
                    nodeAddr = getNodeBranchRight(nodeAddr);
                } else {
                    nodeAddr = getNodeBranchLeft(nodeAddr);
                }

                depthMask >>= 1;
                continue;
            }

            break;
        }

        if (nodeType == NodeType.Leaf) {
            bytes32 leafKeyHash = getNodeLeafKeyHash(proof, nodeAddr);

            if (leafKeyHash == keyHash) {
                return (true, "ASDF");
            } else {
                return (false, "");
            }
        } else if (nodeType == NodeType.WitnessLeaf) {
            bytes32 leafKeyHash = getNodeLeafKeyHash(proof, nodeAddr);

            require(leafKeyHash != keyHash, "incomplete tree (WitnessLeaf)");

            return (false, "");
        } else if (nodeType == NodeType.Empty) {
            return (false, "");
        } else {
            require(false, "incomplete tree (Witness)");
        }
    }
}
