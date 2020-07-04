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


    struct Proof {
        bytes encoded;

        uint256 numStrands;
        uint256 strandStateAddr; // memory address where strand states start
        uint256 startOfCmds; // offset within encoded where cmds start
    }

    // Strand state:
    //     uint256: [0 padding...] [4 bytes: encodedStrandOffset] [1 byte: depth] [1 byte: merged] [4 bytes: next] [4 bytes: nodeAddr]

    // Node:
    //     uint256: [0 padding...] [nodeType specific] [1 byte: nodeType]
    //                Leaf: [4 bytes: encodedStrandOffset]
    //         WitnessLeaf: [4 bytes: encodedStrandOffset]
    //              Branch: [4 bytes: leftNodeAddr] [4 bytes: rightNodeAddr]
    //     bytes32: [nodeHash]

    function getStrandState(Proof memory proof, uint256 strandIndex) private returns (uint256 strandState) {
        uint256 strandStateAddr = proof.strandStateAddr;

        assembly {
            let addr := add(strandStateAddr, mul(strandIndex, 32)) // FIXME shift left
            strandState := mload(addr)
        }
    }

    function getStrandKeyHash(Proof memory proof, uint256 strandState) private returns (bytes32 keyHash) {
        uint256 encodedStrandOffset = strandState >> (10*8);
        keyHash = BytesLib.toBytes32(proof.encoded, encodedStrandOffset + 2);
    }



    function importProof(bytes memory encoded) internal returns (Proof memory) {
        Proof memory proof;

        proof.encoded = encoded;

        _parseStrands(proof);
        _processCmds(proof);

        return proof;
    }


    function _parseStrands(Proof memory proof) private {
        bytes memory encoded = proof.encoded;
        uint256 offset = 0; // into proof.encoded
        uint256 numStrands = 0;

        require(BytesLib.toUint8(encoded, offset++) == 0, "Only CompactNoKeys encoding supported");

        // Setup strand state

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
                strandStateMemOffset := add(mload(0x40), mul(64, numStrands)) // FIXME shift left
            }

            bytes32 nodeHash;

            if (strandType == StrandType.WitnessEmpty) {
                nodeHash = 0x0;
            } else {
                assembly {
                    // Temporarily arrange it so we can compute strand nodeHash in-place
                    mstore(strandStateMemOffset, keyHash)
                    mstore(add(strandStateMemOffset, 32), valHash)
                    mstore8(add(strandStateMemOffset, 64), 0) // free memory not guaranteed to be 0
                    nodeHash := keccak256(strandStateMemOffset, 65)

                    // Now write out the nodeHash over-top
                    mstore(strandStateMemOffset, nodeHash)
                }
            }

            numStrands++; // happens before we generate strandState, since next points to following

            uint256 strandState = (encodedStrandOffset << (6*8)) | (depth << (5*8)) | numStrands;

            assembly {
                mstore(add(strandStateMemOffset, 32), strandState) // linked list pointer
            }
        }

        // Bump free memory pointer over strand state we've just setup

        uint256 strandStateAddr;
        assembly {
            strandStateAddr := mload(0x40)
            mstore(0x40, add(mload(0x40), mul(64, numStrands))) // FIXME shift left
        }

        // Make last strand's next point to 0xFFFFFFFF (sentinel null value)

        if (numStrands != 0)  {
            assembly {
                let lastStrandStateAddr := sub(mload(0x40), 0x20)
                mstore(lastStrandStateAddr, or(mload(lastStrandStateAddr), 0xFFFFFFFF))
            }
        }

        // Output

        proof.numStrands = numStrands;
        proof.strandStateAddr = strandStateAddr;
        proof.startOfCmds = offset;
    }


    function _processCmds(Proof memory proof) private {
        bytes memory encoded = proof.encoded;
        uint256 offset = proof.startOfCmds;


        uint256 currStrand = proof.numStrands - 1;

        while (offset < encoded.length) {
            uint8 cmd = BytesLib.toUint8(encoded, offset++);
            console.log(cmd);

            if ((cmd & 0x80) == 0) {
                if (cmd == 0) {
                    // merge
                } else {
                    // hashing
                    bool started = false;

                    (bytes32 nodeHash, uint256 strandState) = getStrandState(proof, currStrand);
                    bytes32 keyHash = getStrandKeyHash(proof, strandState);
                    console.logBytes32(keyHash);

                    for (uint i=0; i<7; i++) {
                        if (started) {
                            if ((cmd & 1) != 0) {
                                // HashProvided
                                bytes32 witness = BytesLib.toBytes32(encoded, offset);
                                console.logBytes32(witness);
                                offset += 32;
                            } else {
                                // HashEmpty
                            }
                        } else {
                            if ((cmd & 1) != 0) started = true;
                        }

                        cmd >>= 1;
                    }
                }
            } else {
                // jump
            }
        }
    }
}
