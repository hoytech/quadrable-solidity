const bre = require("@nomiclabs/buidler");
const { expect } = require("chai");

const child_process = require('child_process');

const quadb = '../quadrable/quadb';




let testSpecs = [];

testSpecs.push({
    desc: 'single branch inclusion',
    data: {
        a: 'b',
        b: 'c',
    },
    inc: ['a'],
    non: [],
    err: ['b'],
});


testSpecs.push({
    desc: '1000 records, both types of non-inclusion',
    data: makeData(1000, i => [i+1, i+1]),
    inc: ['3', '4'],
    non: [
        '5000', // WitnessEmpty
        '5001', // WitnessLeaf
    ],
    err: [
        'b',
    ],
});



testSpecs.push({
    desc: 'long key/value',
    data: {
        ['key'.repeat(100)]: 'value'.repeat(1000),
    },
    inc: ['key'.repeat(100)],
})





async function main() {
    let quadb_dir = './quadb-test-dir';
    let quadb_cmd = `${quadb} --db ${quadb_dir}`;

    child_process.execSync(`mkdir -p ${quadb_dir}`);
    child_process.execSync(`rm -f ${quadb_dir}/*.mdb`);


    let specsDevMode = testSpecs.filter(s => s.dev);
    if (specsDevMode.length) {
        testSpecs = specsDevMode;
        console.log("RUNNING IN DEV MODE");
    }


    const Test = await ethers.getContractFactory("Test");
    const test = await Test.deploy();
    await test.deployed();

    for (let spec of testSpecs) {
        console.log(`Running test: ${spec.desc}`);

        child_process.execSync(`${quadb_cmd} checkout`);

        let rootHex, proofHex;

        {
            let input = '';

            for (let key of Object.keys(spec.data)) {
                input += `${key},${spec.data[key]}\n`;
            }

            child_process.execSync(`${quadb_cmd} import`, { input, });
            rootHex = child_process.execSync(`${quadb_cmd} root`).toString().trim();

            let proofKeys = (spec.inc || []).concat(spec.non || []).join(' ');

            proofHex = child_process.execSync(`${quadb_cmd} exportProof --hex -- ${proofKeys}`).toString().trim();
        }

        let res = await test.testProof(proofHex, spec.inc.map(i => Buffer.from(i)), [], []);
        expect(res[0]).to.equal(rootHex);
        for (let i = 0; i < spec.inc.length; i++) {
            let valHex = res[1][i];
            valHex = valHex.substr(2); // remove 0x prefix
            expect(Buffer.from(valHex, 'hex').toString()).to.equal(spec.data[spec.inc[i]]);
        }

        if (spec.non && spec.non.length) {
            let res = await test.testProof(proofHex, spec.non.map(i => Buffer.from(i)), [], []);
            for (let i = 0; i < spec.non.length; i++) {
                expect(res[1][i]).to.equal('0x');
            }
        }

        for (let e of (spec.err || [])) {
            let threw;
            try {
                await test.testProof(proofHex, [Buffer.from(e)], [], []);
            } catch (e) {
                threw = '' + e;
            }
            expect(threw).to.not.be.undefined;
            expect(threw).to.contain("incomplete tree");
        }
    }
}


function makeData(n, cb) {
    let output = {};
    for (let i of Array.from(Array(n).keys())) {
        let [k, v] = cb(i);
        output[k] = '' + v;
    }
    return output;
}


main()
    .then(() => process.exit(0))
    .catch(error => {
      console.error(error);
      process.exit(1);
    });
