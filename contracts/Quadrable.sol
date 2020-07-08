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

        uint256 rootNodeAddr;
    }

    // Strand state (128 bytes):
    //     uint256: [0 padding...] [1 byte: depth] [1 byte: merged] [4 bytes: next] [4 bytes: nodeAddr]
    //     [32 bytes: keyHash]
    //     [64 bytes: possibly containing leaf node for this strand]

    // Node (64 bytes):
    //     uint256 nodeContents: [0 padding...] [nodeType specific (see below)] [1 byte: nodeType]
    //                Leaf: [4 bytes: valAddr] [4 bytes: valLen] [4 bytes: keyHashAddr]
    //         WitnessLeaf: [4 bytes: keyHashAddr]
    //             Witness: unused
    //              Branch: [4 bytes: parentNodeAddr] [4 bytes: leftNodeAddr] [4 bytes: rightNodeAddr]
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

    function buildNodeContentsLeaf(uint256 valAddr, uint256 valLen, uint256 keyHashAddr) private pure returns (uint256 nodeContents) {
        nodeContents = valAddr << (9*8) |
                       valLen << (5*8) |
                       keyHashAddr << (1*8) |
                       uint256(NodeType.Leaf);
    }

    function buildNodeLeaf(uint256 nodeContents, uint256 valAddr, uint256 valLen, bytes32 keyHash) private pure returns (uint256 nodeAddr) {
        assembly {
            let valHash := keccak256(valAddr, valLen)

            nodeAddr := mload(0x40)

            mstore(0, keyHash)
            mstore(32, valHash)
            let nodeHash := keccak256(0, 65) // relies on most-significant byte of free space pointer being '\0'

            mstore(nodeAddr, nodeContents)
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

        return (nodeContents >> (5*8)) & 0xFFFFFFFF;
    }

    function getNodeBranchRight(uint256 nodeAddr) private pure returns (uint256) {
        uint256 nodeContents;

        assembly {
            nodeContents := mload(nodeAddr)
        }

        return (nodeContents >> (1*8)) & 0xFFFFFFFF;
    }

    function getNodeBranchParent(uint256 nodeAddr) private pure returns (uint256) {
        uint256 nodeContents;

        assembly {
            nodeContents := mload(nodeAddr)
        }

        return nodeContents >> (9*8);
    }

    function setNodeBranchLeft(uint256 nodeAddr, uint256 newAddr) private pure {
        assembly {
            let nodeContents := mload(nodeAddr)
            nodeContents := and(not(shl(mul(5, 8), 0xFFFFFFFF)), nodeContents) // FIXME: check this is getting constant folded
            nodeContents := or(nodeContents, shl(mul(5, 8), newAddr))
            mstore(nodeAddr, nodeContents)
        }
    }

    function setNodeBranchRight(uint256 nodeAddr, uint256 newAddr) private pure {
        assembly {
            let nodeContents := mload(nodeAddr)
            nodeContents := and(not(shl(mul(1, 8), 0xFFFFFFFF)), nodeContents) // FIXME: check this is getting constant folded
            nodeContents := or(nodeContents, shl(mul(1, 8), newAddr))
            mstore(nodeAddr, nodeContents)
        }
    }

    function setNodeBranchParent(uint256 nodeAddr, uint256 newAddr) private pure {
        assembly {
            let nodeContents := mload(nodeAddr)
            nodeContents := and(not(shl(mul(9, 8), 0xFFFFFFFF)), nodeContents) // FIXME: check this is getting constant folded
            nodeContents := or(nodeContents, shl(mul(9, 8), newAddr))
            mstore(nodeAddr, nodeContents)
        }
    }

    // FIXME: merge these?
    function getNodeLeafKeyHashAddr(uint256 nodeAddr) private pure returns (uint256 keyHashAddr) {
        assembly {
            let nodeContents := mload(nodeAddr)
            keyHashAddr := and(shr(mul(1, 8), nodeContents), 0xFFFFFFFF)
        }
    }

    function getNodeLeafKeyHash(uint256 nodeAddr) private pure returns (bytes32 keyHash) {
        uint256 keyHashAddr = getNodeLeafKeyHashAddr(nodeAddr);

        assembly {
            keyHash := mload(keyHashAddr)
        }
    }

    function getNodeLeafVal(uint256 nodeAddr) private pure returns (uint256 valAddr, uint256 valLen) {
        assembly {
            let nodeContents := mload(nodeAddr)
            valAddr := and(shr(mul(9, 8), nodeContents), 0xFFFFFFFF)
            valLen := and(shr(mul(5, 8), nodeContents), 0xFFFFFFFF)
        }
    }


    function importProof(bytes memory encoded) internal pure returns (Proof memory) {
        Proof memory proof;

        proof.encoded = encoded;

        _parseStrands(proof);
        _processCmds(proof);

        (uint256 strandState,) = getStrandState(proof, 0);
        (uint256 depth,, uint256 next,) = unpackStrandState(strandState); // FIXME: use individual getters
        require(next == proof.numStrands, "next linked list not empty");
        require(depth == 0, "strand depth not at root");

        proof.rootNodeAddr = strandStateNodeAddr(strandState);

        return proof;
    }


    function getRoot(Proof memory proof) internal pure returns (bytes32) {
        return getNodeHash(proof.rootNodeAddr);
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
            StrandType strandType = StrandType(BytesLib.toUint8(encoded, offset++));
            if (strandType == StrandType.Invalid) break;

            uint8 depth = BytesLib.toUint8(encoded, offset++);

            uint256 keyHashAddr;
            assembly { keyHashAddr := add(add(encoded, 0x20), offset) }
            bytes32 keyHash = BytesLib.toBytes32(encoded, offset);
            offset += 32;

            uint256 nodeContents;
            bytes32 valHash;

            if (strandType == StrandType.Leaf) {
                uint256 valLen = 0;
                uint8 b;
                do {
                    b = BytesLib.toUint8(encoded, offset++); 
                    valLen = (valLen << 7) | (b & 0x7F);
                } while ((b & 0x80) != 0);

                uint256 valAddr;

                assembly {
                    valAddr := add(add(encoded, 0x20), offset)
                    valHash := keccak256(valAddr, valLen)
                }

                nodeContents = buildNodeContentsLeaf(valAddr, valLen, keyHashAddr);

                offset += valLen;
            } else if (strandType == StrandType.WitnessLeaf) {
                nodeContents = keyHashAddr << (1*8) |
                               uint256(NodeType.WitnessLeaf);

                valHash = BytesLib.toBytes32(encoded, offset);
                offset += 32;
            }

            uint256 strandState = packStrandState(depth, 0, numStrands+1, 0);

            assembly {
                let strandStateMemOffset := add(mload(0x40), mul(128, numStrands)) // FIXME shift left

                if iszero(eq(strandType, 2)) { // Only if *not* StrandType.WitnessEmpty
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

    function _processCmds(Proof memory proof) private pure {
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




    // FIXME
    // https://github.com/ethereum/solidity-examples/blob/master/src/unsafe/Memory.sol
    uint internal constant WORD_SIZE = 32;
    function copy(uint src, uint dest, uint len) private pure {
        // Copy word-length chunks while possible
        for (; len >= WORD_SIZE; len -= WORD_SIZE) {
            assembly {
                mstore(dest, mload(src))
            }
            dest += WORD_SIZE;
            src += WORD_SIZE;
        }

        // Copy remaining bytes
        uint mask = 256 ** (WORD_SIZE - len) - 1;
        assembly {
            let srcpart := and(mload(src), not(mask))
            let destpart := and(mload(dest), mask)
            mstore(dest, or(destpart, srcpart))
        }
    }


    function get(Proof memory proof, bytes32 keyHash) internal pure returns (bool found, bytes memory) {
        uint256 nodeAddr = proof.rootNodeAddr;
        uint256 depthMask = 1 << 255;
        NodeType nodeType;

        while(true) {
            nodeType = getNodeType(nodeAddr);

            if (nodeType == NodeType.Branch) {
                if ((uint256(keyHash) & depthMask) == 0) {
                    nodeAddr = getNodeBranchLeft(nodeAddr);
                } else {
                    nodeAddr = getNodeBranchRight(nodeAddr);
                }

                depthMask >>= 1;
                continue;
            }

            break;
        }

        if (nodeType == NodeType.Leaf) {
            bytes32 leafKeyHash = getNodeLeafKeyHash(nodeAddr);

            if (leafKeyHash == keyHash) {
                (uint256 valAddr, uint256 valLen) = getNodeLeafVal(nodeAddr);

                bytes memory val;
                uint256 copyDest;

                assembly {
                    val := mload(0x40)
                    mstore(val, valLen)
                    copyDest := add(val, 32)
                    mstore(0x40, add(val, add(valLen, 32)))
                }

                copy(valAddr, copyDest, valLen);

                return (true, val);
            } else {
                return (false, "");
            }
        } else if (nodeType == NodeType.WitnessLeaf) {
            bytes32 leafKeyHash = getNodeLeafKeyHash(nodeAddr);

            require(leafKeyHash != keyHash, "incomplete tree (WitnessLeaf)");

            return (false, "");
        } else if (nodeType == NodeType.Empty) {
            return (false, "");
        } else {
            require(false, "incomplete tree (Witness)");
        }
    }

    function put(Proof memory proof, bytes32 keyHash, bytes memory val) internal pure {
        uint256 nodeAddr = proof.rootNodeAddr;
        uint256 depthMask = 1 << 255;
        NodeType nodeType;
        uint256 parentNodeAddr = 0;

        while(true) {
            nodeType = getNodeType(nodeAddr);

            if (nodeType == NodeType.Branch) {
                parentNodeAddr = nodeAddr;

                if ((uint256(keyHash) & depthMask) == 0) {
                    nodeAddr = getNodeBranchLeft(nodeAddr);
                } else {
                    nodeAddr = getNodeBranchRight(nodeAddr);
                }

                setNodeBranchParent(nodeAddr, parentNodeAddr);

                depthMask >>= 1;
                continue;
            }

            break;
        }


        // Do splitting

        if (nodeType == NodeType.Leaf || nodeType == NodeType.WitnessLeaf) {
            bytes32 foundKeyHash = getNodeLeafKeyHash(nodeAddr);

            if (foundKeyHash != keyHash) {
                uint256 leafNodeAddr = nodeAddr;

                while (true) {
                    nodeAddr = buildNodeBranch(0, 0);
                    setNodeBranchParent(nodeAddr, parentNodeAddr);

                    parentNodeAddr = nodeAddr;
                    if ((uint256(keyHash) & depthMask) != (uint256(foundKeyHash) & depthMask)) break;
                    depthMask >>= 1;
                }

                if ((uint256(keyHash) & depthMask) == 0) {
                    setNodeBranchRight(nodeAddr, leafNodeAddr);
                } else {
                    setNodeBranchLeft(nodeAddr, leafNodeAddr);
                }

                depthMask >>= 1;
            }
        } else if (nodeType == NodeType.Empty) {
            // fall through
        } else {
            require(false, "incomplete tree (Witness)");
        }


        // Construct new Leaf

        uint256 keyHashAddr;
        uint256 valLen;
        uint256 valAddr;

        assembly {
            keyHashAddr := mload(0x40)
            mstore(keyHashAddr, keyHash)
            mstore(0x40, add(keyHashAddr, 32))

            valLen := mload(val)
            valAddr := add(val, 32)
        }

        nodeAddr = buildNodeLeaf(buildNodeContentsLeaf(valAddr, valLen, keyHashAddr), valAddr, valLen, keyHash);


        // Update path back up the tree

        while (parentNodeAddr != 0) {
            depthMask <<= 1;

            uint256 leftNodeAddr;
            uint256 rightNodeAddr;

            if ((uint256(keyHash) & depthMask) == 0) {
                leftNodeAddr = nodeAddr;
                rightNodeAddr = getNodeBranchRight(parentNodeAddr);
            } else {
                leftNodeAddr = getNodeBranchLeft(parentNodeAddr);
                rightNodeAddr = nodeAddr;
            }

            parentNodeAddr = getNodeBranchParent(parentNodeAddr);
            nodeAddr = buildNodeBranch(leftNodeAddr, rightNodeAddr); // FIXME: can we re-use the branch memory?
        }

        proof.rootNodeAddr = nodeAddr;
    }
}
