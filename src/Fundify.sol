// SPDX-License-Identifier: Apache-2.0
pragma solidity ^0.8.22;

struct Project {
    address owner; // Wallet address of the project's publisher
    uint256 index; // Index to query off chain database using owner and index, starts from 0 and onwards
    uint256 goal; // Total ETH needed for the project
    uint256 milestones; // Number of milestones, if 2 then it's 50% and 100%
    // if 3 then 33, 66, 99, basically divide the goal by milestones, max 20
    uint256 funded; // Amount of ETH funded
    uint256 released; // Amount of ETH released
    uint256 defunded; // Amount of ETH defuned
    bool ended; // Project funding is going on or not
}

struct Investment {
    address projectOwner; // Wallet address of the project's publisher
    uint256 projectIndex; // Nth project of the project owner that user funded
    uint256 amount; // Amount of ETH funded
    uint256 withdrawn; // Amount of ETH defunded
}

contract Fundify {
    mapping(address => mapping(uint256 => Project)) projects;
    mapping(address => uint256) projectCount;
    mapping(address => mapping(uint256 => Investment)) investments;
    mapping(address => uint256) investmentCount;

    error InvalidInput();
    error InvalidFunding();
    error ProjectEnded();
    error EthereumTransferFailed();

    event ProjectCreated(
        address owner,
        uint256 index,
        uint256 goal,
        uint256 milestones,
        uint256 timestamp
    );
    event ProjectFunded(
        address funder,
        uint256 amount,
        address projectOwner,
        uint256 projectIndex,
        uint256 timestamp
    );
    event ProjectDefunded(
        address funder,
        uint256 amount,
        address projectOwner,
        uint256 projectIndex,
        uint256 timestamp
    );
    event ProjectFundsReleased(
        address owner,
        uint256 index,
        uint256 amount,
        uint256 timestamp
    );

    function createProject(uint256 _goal, uint256 _milestones) public {
        if (_goal == 0) revert InvalidInput();
        if (_milestones == 0 || _milestones > 5) revert InvalidInput();
        uint256 projectIndex = projectCount[msg.sender]++;
        Project storage project = projects[msg.sender][projectIndex];
        project.owner = msg.sender;
        project.index = projectIndex;
        project.goal = _goal;
        project.milestones = _milestones;
        project.funded = 0;
        project.released = 0;
        project.defunded = 0;
        project.ended == false;
        emit ProjectCreated(
            msg.sender,
            projectIndex,
            _goal,
            _milestones,
            block.timestamp
        );
    }

    function fundProject(
        address _projectOwner,
        uint256 _projectIndex,
        uint256 _investmentIndex
    ) external payable {
        if (_projectOwner == address(0)) revert InvalidInput();
        if (_projectIndex == 0) revert InvalidInput();
        if (projectCount[_projectOwner] < _projectIndex) revert InvalidInput();
        if (msg.value == 0) revert InvalidFunding();
        Project storage project = projects[msg.sender][_projectIndex];
        if (project.ended) revert ProjectEnded();
        uint256 amountAfterFunding = project.funded + msg.value;
        if (amountAfterFunding > project.goal) revert InvalidInput();
        uint256 totalInvestments = investmentCount[msg.sender];
        uint256 investmentIndex = 0;
        if (totalInvestments == 0) {
            investmentIndex = 1;
        } else if (totalInvestments < _investmentIndex) {
            if (totalInvestments + 1 == _investmentIndex) {
                investmentIndex = _investmentIndex;
            } else revert InvalidInput();
        } else {
            investmentIndex = _investmentIndex;
        }
        Investment storage investment = investments[msg.sender][
            investmentIndex
        ];
        investment.projectOwner = _projectOwner;
        investment.projectIndex = _projectIndex;
        investment.amount += msg.value;
        project.funded = amountAfterFunding;
        emit ProjectFunded(
            msg.sender,
            msg.value,
            _projectOwner,
            _projectIndex,
            block.timestamp
        );
    }

    function defundProject(
        address _projectOwner,
        uint256 _projectIndex,
        uint256 _investmentIndex,
        uint256 _amount
    ) external payable {
        if (_projectOwner == address(0)) revert InvalidInput();
        if (_projectIndex == 0) revert InvalidInput();
        if (projectCount[_projectOwner] < _projectIndex) revert InvalidInput();
        if (msg.value == 0) revert InvalidFunding();
        Project storage project = projects[msg.sender][_projectIndex];
        if (project.ended) revert ProjectEnded();
        Investment storage investment = investments[msg.sender][
            _investmentIndex
        ];
        if (investment.projectOwner != _projectOwner) revert InvalidInput();
        if (investment.projectIndex != _projectIndex) revert InvalidInput();
        uint256 remainingAmount = investment.amount - investment.withdrawn;
        if (remainingAmount < _amount) revert InvalidInput();
        investment.withdrawn += _amount;
        project.defunded += _amount;
        (bool sent, ) = payable(msg.sender).call{value: _amount}("");
        if (!sent) revert EthereumTransferFailed();
        emit ProjectDefunded(
            msg.sender,
            _amount,
            _projectOwner,
            _projectIndex,
            block.timestamp
        );
    }

    function releaseFunds(
        uint256 _projectIndex,
        uint256 _amount
    ) external payable {
        if (_projectIndex == 0) revert InvalidInput();
        if (_amount == 0) revert InvalidInput();
        if (projectCount[msg.sender] < _projectIndex) revert InvalidInput();
        Project storage project = projects[msg.sender][_projectIndex];
        if (project.ended) revert ProjectEnded();
        uint256 remainingAmount = project.funded -
            (project.defunded + project.released);
        if (remainingAmount < _amount) revert InvalidInput();
        project.released += _amount;
        (bool sent, ) = payable(msg.sender).call{value: _amount}("");
        if (!sent) revert EthereumTransferFailed();
        emit ProjectFundsReleased(
            msg.sender,
            _projectIndex,
            _amount,
            block.timestamp
        );
    }

    // main problem is how funding is being tracked individually
    // investor could take out funds when his inital funds were already released
    // and if later investors want to defund, they can't since earlier investor took all
}
