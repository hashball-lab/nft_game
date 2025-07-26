// SPDX-License-Identifier: MIT
pragma solidity ^0.8.27;

interface MyNFT {
    function balanceOf(address account) external view returns (uint256);
}

interface MyCommittee {
    function get_current_epoch_starttime() external view returns(uint256, uint256);
}

contract NFTReward {
    MyNFT public mynft;
    MyCommittee public mycommittee;

    struct NumHash{
        bytes32 numhash; 
        uint32[3] nums;
        bool claimed;
    }

    struct PrizeRecord{
        uint256 epoch;
        uint256 prize;
        bytes32 numhash;
        uint32[3] nums;
        address[] addresses;
    }

    struct MyPlayRecord{
        uint256 epoch;
        uint256 win_prize;
        bytes32 numhash;
        uint32[3] nums;
        bool win;
        bool claimed;
    }

    address public committee_contract_address;
    address public nft_contract_address;
    address public owner;   
    bool public initialized;
    uint256 public nft_total_prize;
    uint256 constant public BET_DIFF = 60*60*46;
    uint256 constant public EACH_MAX_PRIZE = 6 * (10 ** 15);

    mapping (uint256 => NumHash) private epoch_prize_nums;//epoch=>NumHash
    mapping (uint256 => uint256) private epoch_prizes;//epoch=>prize
    mapping (uint256 => uint256) private epoch_prize_eachaddress;//epoch=>prize
    mapping (address => mapping(uint256 => NumHash)) private myepoch_nums;//address=>epoch=>NumHash
    mapping (uint256 => mapping(bytes32 => address[])) private epoch_hash_address;//epoch=>hash=>address[]
    mapping (address => bool) private authorize_draw_winer;//authorize


    modifier onlyOwner(){
        require(msg.sender == owner, "not owner");
        _;
    }

    modifier onlyDrawWinner(){
        require(authorize_draw_winer[msg.sender], "not authorize");
        _;
    }

    function initialize(address _owner) public{
        require(!initialized, "already initialized");
        initialized = true;
        owner = _owner;
    }

    receive() external payable {
        nft_total_prize += msg.value;
    }
    fallback() external payable {}

    function set_mycommittee(address _mycommittee) public onlyOwner{
        mycommittee = MyCommittee(_mycommittee);
        committee_contract_address = _mycommittee;
    }

    function set_mynft(address _mynft) public onlyOwner{
        mynft = MyNFT(_mynft);
        nft_contract_address = _mynft;
    }

    function set_authorize_draw_winner_address(address _myaddress, bool _true_false) public onlyOwner{
        authorize_draw_winer[_myaddress] = _true_false;
    }

    function play_numbers(uint32[3] calldata _nums) public {
        (uint256 epoch, uint256 starttime) = mycommittee.get_current_epoch_starttime();
        require(epoch > 0, 'not start');
        require(starttime > 0, 'epoch not start');
        require(block.timestamp < BET_DIFF + starttime, 'time exceed');
        require(myepoch_nums[msg.sender][epoch].numhash == bytes32(0), "already play in epoch");
        require(mynft.balanceOf(msg.sender) > 0, "not nft holder");
        
        bytes32 _hash = keccak256(abi.encodePacked(_nums));
        myepoch_nums[msg.sender][epoch].numhash = _hash;
        myepoch_nums[msg.sender][epoch].nums = _nums;
        myepoch_nums[msg.sender][epoch].claimed = false;

        epoch_hash_address[epoch][_hash].push(msg.sender);        
    }

    function start_reward(uint256 _epoch, bytes32 _combine_random_hash) public onlyDrawWinner{
        for(uint256 i = 0; i < 3; i++) {
            bytes32 _numhash = keccak256(abi.encodePacked(_combine_random_hash, i));
            epoch_prize_nums[_epoch].nums[i] = uint32(uint256(_numhash) % 10);
            //epoch_prize_nums[_epoch].nums[i] = uint32(uint256(_numhash) % 2);//for test
        }
        epoch_prize_nums[_epoch].numhash = keccak256(abi.encodePacked(epoch_prize_nums[_epoch].nums));

        uint256 len = epoch_hash_address[_epoch][epoch_prize_nums[_epoch].numhash].length;
        if(len > 0){//someone win
            if(nft_total_prize/2 > (len * EACH_MAX_PRIZE)){
                epoch_prizes[_epoch] = (len * EACH_MAX_PRIZE);
                epoch_prize_eachaddress[_epoch] = EACH_MAX_PRIZE;
            }else{
                epoch_prizes[_epoch] = nft_total_prize/2;
                epoch_prize_eachaddress[_epoch] = (nft_total_prize/2)/len;
            }
            nft_total_prize -= epoch_prizes[_epoch];
        }else{//no win
            epoch_prizes[_epoch] = nft_total_prize/2;
            epoch_prize_eachaddress[_epoch] = 0;
        }
    }

    function claim(uint256 _epoch) public{
        (uint256 epoch, ) = mycommittee.get_current_epoch_starttime();
        require(_epoch >= 1 && _epoch < epoch, 'epoch not allow');
        if(myepoch_nums[msg.sender][_epoch].numhash == epoch_prize_nums[_epoch].numhash){
            if(!myepoch_nums[msg.sender][_epoch].claimed){
                myepoch_nums[msg.sender][_epoch].claimed = true;
                (bool success, ) = (msg.sender).call{value: epoch_prize_eachaddress[_epoch]}("");
                if(!success){
                    revert('call failed');
                }
            }else{
                revert('already claimed');
            }
        }else{
            revert('not win');
        }
    }

    function get_prize_record(uint256 from, uint256 to) view public returns(PrizeRecord[] memory){
        require(from > to, 'not allow');
        PrizeRecord[] memory prizerecords = new PrizeRecord[](from-to);
        
        uint256 _index = 0;
        for(uint256 i = from; i > to; i--){
            prizerecords[_index] =PrizeRecord(i, epoch_prizes[i], epoch_prize_nums[i].numhash, epoch_prize_nums[i].nums, epoch_hash_address[i][epoch_prize_nums[i].numhash]);
            _index ++;
        }

        return prizerecords;
    }

    function get_mycurrent_play_record(address _addr) view public returns(NumHash memory){
        (uint256 epoch, ) = mycommittee.get_current_epoch_starttime();
        return myepoch_nums[_addr][epoch];
    }

    function get_myplay_record(address _addr, uint256 from, uint256 to) view public returns(MyPlayRecord[] memory){
        require(from > to, 'not allow');
        uint256 true_index = 0;
        for(uint256 j = from; j > to; j--){
            if(myepoch_nums[_addr][j].numhash != bytes32(0)){
                true_index++;
            }
        }

        MyPlayRecord[] memory myplayrecords = new MyPlayRecord[](true_index);
        uint256 _index = 0;
        for(uint256 i = from; i > to; i--){
            if(myepoch_nums[_addr][i].numhash != bytes32(0)){
                myplayrecords[_index] = MyPlayRecord(i, epoch_prize_eachaddress[i], myepoch_nums[_addr][i].numhash, myepoch_nums[_addr][i].nums, myepoch_nums[_addr][i].numhash == epoch_prize_nums[i].numhash, myepoch_nums[_addr][i].claimed);
                _index ++;
            }
        }
        return myplayrecords;
    }

    

    


}
