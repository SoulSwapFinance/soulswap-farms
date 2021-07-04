const SoulToken = artifacts.require('SoulToken.sol');
const MasterChef = artifacts.require('MasterChef.sol');
const SeanceCircle = artifacts.require('SeanceCircle.sol');
const SoulVault = artifacts.require('SoulVault.sol');

module.exports = async function(deployer) {

  // Deploy Soul Token Contract
  await deployer.deploy(SoulToken)
  const soulToken = await SoulToken.deployed()
  await soulToken.mint(process.env.ADMIN_ADDRESS, web3.utils.toWei('50000000000000000', 'gwei'))

  // Deploy Seance Token Contract
  await deployer.deploy(SeanceCircle, soulToken.address)
  const seanceToken = await SeanceCircle.deployed()

// Deploy MasterChef Contract
  await deployer.deploy(
    MasterChef,
    soulToken.address,
    seanceToken.address,
    process.env.ADMIN_ADDRESS, // Your address where you get SOUL tokens - should be a multisig
    process.env.TREASURY_ADDRESS, // Your address where you collect fees - should be a multisig
    '1620819000', // process.env.START_TIME, // Block timestamp when token baking begins
  )
  const masterChef = await MasterChef.deployed()

// Deploy SoulVault Contract
await deployer.deploy(
  SoulVault,
  soulToken.address, // TOKEN
  seanceToken.address, // RECEIPT TOKEN
  masterChef.address, // MASTERCHEF
  process.env.ADMIN_ADDRESS, // Your address where you get SOUL tokens - should be a multisig
  process.env.TREASURY_ADDRESS, // Your address where you collect fees - should be a multisig
)

  // Make MasterChef contract token owner for soulToken and seanceToken
  await soulToken.transferOwnership(masterChef.address)
  await seanceToken.transferOwnership(masterChef.address)

}
