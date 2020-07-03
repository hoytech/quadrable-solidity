const bre = require("@nomiclabs/buidler");

async function main() {
  const Test = await ethers.getContractFactory("Test");
  const test = await Test.deploy();

  await test.deployed();

  console.log("Test deployed to:", test.address);
}

main()
  .then(() => process.exit(0))
  .catch(error => {
    console.error(error);
    process.exit(1);
  });
