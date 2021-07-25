const SoulPower = artifacts.require('SoulPower.sol');
const SeanceCircle = artifacts.require('SeanceCircle.sol');
const SpellBound = artifacts.require('SpellBound.sol');
const SoulSummoner = artifacts.require('SoulSummoner.sol');
const SoulVault = artifacts.require('SoulVault.sol');

module.exports = async function(deployer) {

  // deploy soul
  await deployer.deploy(SoulPower)
  const soulPower = await SoulPower.deployed()
  await soulPower.mint(process.env.ADMIN_ADDRESS, web3.utils.toWei('50000000000000000', 'gwei'))

  // deploy seance
  await deployer.deploy(SeanceCircle, soulPower.address)
  const seanceCircle = await SeanceCircle.deployed()

  // deploy spell
  await deployer.deploy(SpellBound)
  const spellBound = await SpellBound.deployed()
  console.log('spellBound: ', spellBound.address)

// deploy summoner
  await deployer.deploy(SoulSummoner)
  const soulSummoner = await SoulSummoner.deployed()

// deploy vault
await deployer.deploy(
  SoulVault,
  soulPower.address, // soul
  seanceCircle.address, // seance
  soulSummoner.address // summoner
)

  // make SoulSummoner contract an operator for soulPower and seanceCircle
  await soulPower.addOperator(soulSummoner.address)
  await seanceCircle.addOperator(soulSummoner.address)

}
