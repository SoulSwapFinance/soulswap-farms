// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;
import '../libraries/SafeERC20.sol';
import '../libraries/ERC20.sol';

contract Farm {
using SafeERC20 for IERC20;
    address public owner;
    address public manifester;
    IERC20 public rewardToken;
    IERC20 public depositToken;
    uint public duration;
    uint public dailyReward;
    uint public totalRewards;

    bool private isManifested = false;

    constructor() {
        manifester = msg.sender;
    }

        // called once by the factory at time of deployment
    function manifest(
        address _owner,
        address _rewardToken,
        address _depositToken,
        uint _duration,
        uint _dailyReward,
        uint _totalRewards
    ) external {
        require(msg.sender == manifester, "only the manifeser many manifest"); // sufficient check
        require(!isManifested, 'initialize once');
        owner = _owner;
        rewardToken = IERC20(_rewardToken);
        depositToken = IERC20(_depositToken);
        duration = _duration;
        dailyReward = _dailyReward;
        totalRewards = _totalRewards;

        // sets: initialization state.
        isManifested = true;
    }
}

contract FarmManifester {
    bytes32 public constant INIT_CODE_PAIR_HASH = keccak256(abi.encodePacked(type(Farm).creationCode));

    uint256 public totalFarms = 0;
    address[] public allFarms;

    mapping(address => mapping(address => address)) public getFarm; // depositToken, ownerAddress

    event FarmCreated(address indexed ownerAddress, address indexed depositToken, address farm, uint totalFarms);

    function createFarm(address rewardToken, address depositToken, uint duration, uint dailyReward) external returns (address farm) {
        require(rewardToken != depositToken, 'reward and deposit cannot be identical.');
        address ownerAddress = address(msg.sender);
        uint tokenDecimals = ERC20(rewardToken).decimals();
        uint totalRewards = duration * 1 days * dailyReward * tokenDecimals;

        // ensures: unique deposit-owner mapping.
        require(getFarm[depositToken][ownerAddress] == address(0), 'reward already exists'); // single check is sufficient
        
        // checks: the creator has a sufficient balance.
        require(ERC20(rewardToken).balanceOf(msg.sender) >= totalRewards, 'insufficient balance to launch farm');

        // transfers: `totalRewards` to this contract.
        ERC20(rewardToken).transferFrom(msg.sender, address(this), totalRewards);

        bytes memory bytecode = type(Farm).creationCode;
        bytes32 salt = keccak256(abi.encodePacked(depositToken, ownerAddress));
        
        assembly { farm := create2(0, add(bytecode, 32), mload(bytecode), salt) }
        
        // creates: new farm based off of the inputs, then stores as an array.
        Farm(farm).manifest(ownerAddress, rewardToken, depositToken, duration, dailyReward, totalRewards);
        
        // populates: the getFarm mapping
        getFarm[depositToken][ownerAddress] = farm;
        getFarm[ownerAddress][depositToken] = farm; // populate mapping in the reverse direction

        // stores the farm to the allFarms array
        allFarms.push(farm);

        // increments: the total number of farms
        totalFarms++;

        emit FarmCreated(ownerAddress, depositToken, farm, totalFarms);
    }
}