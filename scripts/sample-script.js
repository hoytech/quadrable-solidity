const bre = require("@nomiclabs/buidler");
const { expect } = require("chai");



let testSpecs = [];

testSpecs.push({
    desc: 'a=b, b=c',
    root: "0x7d1c3aaf4be9e074ec8a25b88f1e33f61aebd2b239d2506ccd2f9476080389b1",
    proof: "0x0000013ac225168df54212a25c1c01fd35bebfea408fdac2e31ddd6f80a4bbf9a5f1cb01620f60e2ba9c7804ddaad28e769649f0cfd71246f0ab6d1d56fd8622a7798f42a96c6f",
    inc: [
        ['a', 'b'],
    ],
    non: [
    ],
    err: [
        'b',
    ],
});




// perl -E 'for $i (1..1000) { say "$i,$i" }' | ./quadb import

testSpecs.push({
    desc: '1-1000, inc: 3, 4. non: 5000 5001',
    root: "0x59b88b76092cc8386fcf4e7f7e28530489d7eacdfae773914ec5516cb052a1d1",
    proof: "0x00000e13600b294191fc92924bb3ce4b969c1e7e2bab8f4c93c3fc6d0a51733df3c0600134000c2a80e1ef1d7842f27f2e6be0972bb708b9a135c38860dbe73c27c3486c34f4de01330109650ed8ce37a4ca016960f899232a7a29f723fd75cf8c4efab7095bc4e4608e95650ed8ce37a4ca016960f899232a7a29f723fd75cf8c4efab7095bc4e4608e950208f5000000000000000000000000000000000000000000000000000000000000000fa1635bf4680940616103d08b6a99f5ecddf60d1f090e196d234a3cd2b5f2247684dfe0304787b4dd9e0cfd0d409ea1dbd66d74c70ad4a042786c5c00911b2489f87bdbd60cf8e37b1cc0ed48ded10e54956079a67fd528351491694ba64416c56f60789fb9737cc3243ac1b51e174f48c360bbbfd15c0651892c59f27853d0819b6c64c019e7090f67531a0f78d1d8e1bff074df72e037981d3c95073ff34e9bc8140050c80c92954bd2704d297f51504485f2fb03907a829a77eee5dc08b1c8ad3b86807ff83a94b1123e5d59cd0572a6a7a8e5b10f56521f4afa3a05ffd5797a5c28b119c991ceb773031a75c455e921dba157b36bf27b584d0fbb22ff005ca08d026f94c051b5487e97da930930d745300051f239ec3c6c3ffbc44d2e3e211529473fcfe1d670f242934ea3a5fddbfe8d94b3696f14592d2da83a7bd53874724c4a89d4d21625670cee00111aa44790513a7eaa05c6a03a670603210c83c479b98dab5855afe0ced7140f06257cad46189099d80983f81876affe9a33cb34143aafc0e460e6b093bb3d38a6a8c6a16a547f4116e02409e5a584dd7c57a54d8bebf8f23b07807fca4d8dbee96e685a9c01a17aed868301e193c11ceefe9c48431af50d0e3154d71a580b75235fe697697c882badacd0361d70d91c3afadb17bb4fb0a838a8080f46d999fcf4d5064a852cb0ff53222f0a51803ce054eac5dcf77b7257c5d4164e13d7dd228e7cd94975ce4c3abbd2e83c191883458e608ff9ef820cba76eec9394cfe648617780165fe2eeea7be076734eac8339409bc08a03cbb7bfa7adc2d22fd14587dd66d6a99816f34a1065a22ce0be04d06438d13b47e2cebe1fcbab267604bd3988d15265922a04e50d05a86a32936cee1ec2f2638e3f429a1458541bcb8a2032afef4715a986d94f2b18d4e168d4040e62c9ef50350b3deb19ed94c3bbcda217ee619ac5cd3030e74fa248786fce199bce8de4f9e33d33e190f2f3c3ebe26898f60fcf4fb4245d0efc6f3a89a38c4bfb1b18d4a002f6478a2918e5ace551988adee1e03b31fb1bd0c5d327edebb8de50c5f484c626d2c834a53214b0442faa31606cd598af742f706df39c1261992ef67f74fd2030356ee0ef14fed5b2cb4bd1bc55855c11be14ae75036647b45b149c70452156db5190e046192f02c003f43f7000000",
    inc: [
        ['3', '3'],
        ['4', '4'],
    ],
    non: [
        '5000', // WitnessEmpty
        '5001', // WitnessLeaf
    ],
    err: [
        'b',
    ],
})






async function main() {
    const Test = await ethers.getContractFactory("Test");
    const test = await Test.deploy();
    await test.deployed();

    for (let spec of testSpecs) {
        let res = await test.testProof(spec.proof, spec.inc.map(i => Buffer.from(i[0])), [], []);
        expect(res[0]).to.equal(spec.root);
        for (let i = 0; i < spec.inc.length; i++) {
            let valHex = res[1][i];
            valHex = valHex.substr(2); // remove 0x prefix
            expect(Buffer.from(valHex, 'hex').toString()).to.equal(spec.inc[i][1]);
        }

        if (spec.non && spec.non.length) {
            let res = await test.testProof(spec.proof, spec.non.map(i => Buffer.from(i)), [], []);
            for (let i = 0; i < spec.non.length; i++) {
                expect(res[1][i]).to.equal('0x');
            }
        }

        for (let e of (spec.err || [])) {
            let threw;
            try {
                await test.testProof(spec.proof, [Buffer.from(e)], [], []);
            } catch (e) {
                threw = '' + e;
            }
            expect(threw).to.contain("incomplete tree");
        }
    }
}


main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
