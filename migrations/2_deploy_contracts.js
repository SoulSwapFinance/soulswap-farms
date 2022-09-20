const SoulPower = artifacts.require('SoulPower.sol');
const SeanceCircle = artifacts.require('SeanceCircle.sol');
const SoulSummoner = artifacts.require('SoulSummoner.sol');
const Web3 = require('web3');

console.log(web3);
const THOTH = '0xdffb0b033b8033405f5fb07b08f48c89fa1b4a3d5d5a475c3e2b8df5fbd4da0d'
const FTM_SOUL_LP = '0x10c0AFd7C58916C4025d466E11850c7D79219277' // testnet
const team = '0x81Dd37687c74Df8F957a370A9A4435D873F5e5A9' // mainnet
const dao = '0x1C63C726926197BD3CB75d86bCFB1DaeBcD87250' // mainnet

module.exports = async function(deployer) {
  console.log('please select mode...');
  // SELECTION = 'DEVELOPMENT';
  SELECTION = 'TESTNET';
  console.log('user selected: %s', SELECTION);

  MODE = 
    SELECTION == 'DEVELOPMENT' ?
      web3 = new Web3('ws://localhost:8546')
      : 'TESTNET' ?
        web3 = new Web3('ws://rpc.testnet.fantom.network')
        :  web3 = new Web3('http://rpc.fantom.tools');

  // web3 = new Web3('ws://localhost:8546');

  // deploy soul
  await deployer.deploy(SoulPower)
  // const soul = '0xCF174A6793FA36A73e8fF18A71bd81C985ef5aB5' // testnet
  // const soul = '0xe2fb177009FF39F52C0134E8007FA0e4BaAcBd07' // mainnet
  const soul = await SoulPower.deployed()

  // [seance]: deploy and initialize
  await deployer.deploy(SeanceCircle, soul.address)
  const seance = await SeanceCircle.deployed()
  await seance.initialize(soul.address)    
  console.log('initialized: seance')

// // deploy spell
// await deployer.deploy(SpellBound)
// const spellBound = await SpellBound.deployed()
// console.log('spellBound: ', spellBound.address)

// [summoner]: deploy and initialize
  await deployer.deploy(SoulSummoner)
  const summoner = await SoulSummoner.deployed()

  await summoner.initialize(
    soul.address,     // soul
    seance.address,  // seance
    0, 1000,        // total weight, weight
    1000,          // staking allocation
    14,           // startRate,
    1            // dailyDecay
  )

  // // deploy vault
  // await deployer.deploy(
  //   SoulVault,
  //   soul.address, // soul
  //   seance.address, // seance
  //   summoner.address // summoner
  // )

  // make SoulSummoner contract an operator for soul and seance
  await soul.grantRole(THOTH, summoner.address)
  await seance.addOperator(summoner.address)

  // add new pool [ftm-soul]
  await summoner.addPool(800, FTM_SOUL_LP, true)

  // update accounts to dao and team (multi-sigs) [mainnet-only]
  await summoner.updateAccounts(dao, team) 
}
