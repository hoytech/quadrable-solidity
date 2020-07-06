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
        Leaf, // = 0
        Witness, // = 1
        WitnessLeaf, // = 2
        Branch // = 3
    }


    struct Proof {
        bytes encoded;

        uint256 numStrands;
        uint256 strandStateAddr; // memory address where strand states start
        uint256 startOfCmds; // offset within encoded where cmds start
    }

    // Strand state (128 bytes):
    //     uint256: [0 padding...] [4 bytes: encodedStrandOffset] [1 byte: depth] [1 byte: merged] [4 bytes: next] [4 bytes: nodeAddr]
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

    function getStrandState(Proof memory proof, uint256 strandIndex) private pure returns (uint256 strandState, bytes32 keyHash) {
        uint256 strandStateAddr = proof.strandStateAddr;

        assembly {
            let addr := add(strandStateAddr, mul(strandIndex, 128)) // FIXME shift left
            strandState := mload(addr)
            keyHash := mload(add(addr, 32))
        }
    }

    function packStrandState(uint256 encodedStrandOffset, uint256 depth, uint256 merged, uint256 next, uint256 nodeAddr) private pure returns (uint256 strandState) {
        strandState = encodedStrandOffset << (4*8);
        strandState = (strandState << (1*8)) | depth;
        strandState = (strandState << (1*8)) | merged;
        strandState = (strandState << (4*8)) | next;
        strandState = (strandState << (4*8)) | nodeAddr;

    }

    function unpackStrandState(uint256 strandState) private pure returns (uint256 encodedStrandOffset, uint256 depth, uint256 merged, uint256 next, uint256 nodeAddr) {
        encodedStrandOffset = strandState >> (10*8);
        depth = (strandState >> (9*8)) & 0xFF;
        merged = (strandState >> (8*8)) & 0xFF;
        next = (strandState >> (4*8)) & 0xFFFFFFFF;
        nodeAddr = strandState & 0xFFFFFFFF;
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

    function getNodeHash(uint256 nodeAddr) private pure returns (bytes32 nodeHash) {
        assembly {
            nodeHash := mload(add(nodeAddr, 32))
        }
    }


    function importProof(bytes memory encoded) internal view returns (Proof memory) {
        Proof memory proof;

        proof.encoded = encoded;

        _parseStrands(proof);
        _processCmds(proof);

        (uint256 strandState,) = getStrandState(proof, 0);
        (, uint256 depth,, uint256 next,) = unpackStrandState(strandState);
        require(next == proof.numStrands, "next linked list not empty");
        require(depth == 0, "strand depth not at root");

        return proof;
    }


    function getRoot(Proof memory proof) internal view returns (bytes32) {
        (uint256 strandState,) = getStrandState(proof, 0);
        (,,,, uint256 nodeAddr) = unpackStrandState(strandState);

        bytes32 root = getNodeHash(nodeAddr);
        console.logBytes32(root);
        return root;
    }


    function _parseStrands(Proof memory proof) private view {
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

            uint256 strandStateMemOffset;
            assembly {
                strandStateMemOffset := add(mload(0x40), mul(128, numStrands)) // FIXME shift left
            }

            uint256 strandState = packStrandState(encodedStrandOffset, depth, 0, numStrands+1, 0);

            console.log("HI"); // FIXME: removing this line causes optimizer to mess up?
            if (strandType != StrandType.WitnessEmpty) {
                uint256 nodeContents = (encodedStrandOffset << (1*8)) | uint8(strandType);

                assembly {
                    mstore(0, keyHash)
                    mstore(32, valHash)
                    let nodeHash := keccak256(0, 65) // relies on most-significant byte of free space pointer being '\0'

                    mstore(add(strandStateMemOffset, 64), nodeContents)
                    mstore(add(strandStateMemOffset, 96), nodeHash)
                }

                strandState |= (strandStateMemOffset + 64); // add the following nodeAddr to the strandState
            }

            assembly {
                mstore(strandStateMemOffset, strandState)
                mstore(add(strandStateMemOffset, 32), keyHash)
            }

            numStrands++;
        }

        // Bump free memory pointer over strand state we've just setup

        assembly {
            mstore(0x40, add(mload(0x40), mul(64, numStrands))) // FIXME shift left
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
                if (cmd == 0) {
                    // merge
                } else {
                    // hashing
                    bool started = false;

                    (uint256 strandState, bytes32 keyHash) = getStrandState(proof, currStrand);
                    (uint256 encodedStrandOffset, uint256 depth, uint256 merged, uint256 next, uint256 nodeAddr) = unpackStrandState(strandState);

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

        bytes32 root = getNodeHash(nodeAddr);
        console.logBytes32(root);
                        cmd >>= 1;
                    }

                    uint256 newStrandState = packStrandState(encodedStrandOffset, depth, merged, next, nodeAddr);
                    saveStrandState(proof, currStrand, newStrandState);
                }
            } else {
                // jump
            }
        }
    }
}
