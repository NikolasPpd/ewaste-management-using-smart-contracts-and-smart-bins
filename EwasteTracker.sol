// SPDX-License-Identifier: MIT
pragma solidity ^0.6.6;

contract EwasteTracker {
    address public owner;
    // hardcoded reward amount for demonstation purposes only
    uint256 public _REWARD_ = 1000000000000000000; // 10**18 wei = 1 ether
    mapping(address => Stakeholder) public stakeholderInfo;
    mapping(address => OwnedDevices) public ownedDevices;
    mapping(string => Device) public devices;
    // map stakeholderAddress => partnerAddress => isPartner
    mapping(address => mapping(address => bool)) public stakeholderPartners;
    // match a stakeholder type to a list of possible partner types
    mapping(StkTypes => StkTypes[]) internal stkAllowedPartners;
    // match a stakeholder type to a list of stakeholder types they can transfer devices to
    mapping(StkTypes => StkTypes[]) internal stkAllowedTransfers;

    enum StkTypes {
        Producer,
        Retailer,
        CollectionCenter,
        RecyclingUnit,
        SmartBin,
        _NONE_
    }
    // set length of StkTypes enum
    uint256 constant TYPES_LENGTH = 5;

    struct Stakeholder {
        string name;
        StkTypes stkType;
        address stkAddress;
        uint256 registrationTimestamp;
        uint256 penaltyWei;
    }

    struct OwnedDevices {
        string[] usableDevices;
        uint256 usableCount;
        string[] ewasteDevices;
        uint256 ewasteCount;
    }

    enum DeviceType {
        Usable,
        Ewaste
    }

    struct Device {
        string UID;
        address owner;
        bool returnToProducer;
        DeviceType deviceType;
        // certain attributes (such as model, manufacturer, brand, isFirstHand)
        // have been omitted for the sake of simplicity
    }

    // constructor
    constructor() public {
        owner = msg.sender;

        // set the types of stakeholder partners each stakeholder type can have
        stkAllowedPartners[StkTypes.Producer] = [
            StkTypes.Retailer,
            StkTypes.CollectionCenter
        ];
        stkAllowedPartners[StkTypes.Retailer] = [
            StkTypes.Producer,
            StkTypes.CollectionCenter
        ];
        stkAllowedPartners[StkTypes.CollectionCenter] = [
            StkTypes.Producer,
            StkTypes.Retailer,
            StkTypes.RecyclingUnit,
            StkTypes.SmartBin
        ];
        stkAllowedPartners[StkTypes.RecyclingUnit] = [
            StkTypes.CollectionCenter
        ];
        stkAllowedPartners[StkTypes.SmartBin] = [StkTypes.CollectionCenter];

        // set the types of stakeholders each type can transfer devices to
        stkAllowedTransfers[StkTypes.Producer] = [
            StkTypes.Retailer,
            StkTypes.CollectionCenter
        ];
        stkAllowedTransfers[StkTypes.Retailer] = [
            // TODO: TO CONSUMER (maybe not)
            StkTypes.CollectionCenter
        ];
        stkAllowedTransfers[StkTypes.CollectionCenter] = [
            StkTypes.Producer,
            StkTypes.RecyclingUnit
        ];
        stkAllowedTransfers[StkTypes.RecyclingUnit] = [StkTypes._NONE_];
        stkAllowedTransfers[StkTypes.SmartBin] = [StkTypes.CollectionCenter];
    }

    // MODIFIERS //
    modifier onlyOwner() {
        require(
            msg.sender == owner,
            "Only the contract owner can access this function!"
        );
        _;
    }

    modifier onlyAllowedStakeholders(
        uint8[TYPES_LENGTH] memory _allowedStkTypes
    ) {
        bool isAllowed = false;
        for (uint256 index = 0; index < TYPES_LENGTH; index++) {
            if (
                _allowedStkTypes[uint8(stakeholderInfo[msg.sender].stkType)] ==
                1
            ) {
                isAllowed = true;
                break;
            }
        }
        require(isAllowed, "You are not allowed to use this function!");
        _;
    }

    modifier isPartnerTypeAllowed(address _stkAddress) {
        bool partnerTypeInAllowedList = false;
        for (
            uint256 index = 0;
            index <
            stkAllowedPartners[stakeholderInfo[msg.sender].stkType].length;
            index++
        ) {
            if (
                stkAllowedPartners[stakeholderInfo[msg.sender].stkType][
                    index
                ] == stakeholderInfo[_stkAddress].stkType
            ) {
                partnerTypeInAllowedList = true;
                break;
            }
        }
        require(
            partnerTypeInAllowedList,
            "You can't add this type of partner!"
        );
        _;
    }

    modifier isTransferTypeAllowed(address _stkAddress) {
        bool transferTypeInAllowedList = false;
        for (
            uint256 index = 0;
            index <
            stkAllowedTransfers[stakeholderInfo[msg.sender].stkType].length;
            index++
        ) {
            if (
                stkAllowedTransfers[stakeholderInfo[msg.sender].stkType][
                    index
                ] == stakeholderInfo[_stkAddress].stkType
            ) {
                transferTypeInAllowedList = true;
                break;
            }
        }
        require(
            transferTypeInAllowedList,
            "You can't transfer devices to this type of stakeholder!"
        );
        _;
    }

    modifier arePartners(address _stkAddress) {
        require(
            stakeholderPartners[msg.sender][_stkAddress],
            "You must be partners to perform this action!"
        );
        _;
    }

    // FUNCTIONS //

    // OWNER FUNCTIONS //
    function addAuthorizedStakeholder(
        string memory _name,
        StkTypes _stkType,
        address _stkAddress,
        uint256 _penaltyWei
    ) public onlyOwner {
        stakeholderInfo[_stkAddress] = Stakeholder(
            _name,
            _stkType,
            _stkAddress,
            now,
            _penaltyWei
        );
    }

    function removeAuthorizedStakeholder(address _stkAddress) public onlyOwner {
        delete stakeholderInfo[_stkAddress];
    }

    function setPenalty(address _stkAddress, uint256 _penaltyWei)
        public
        onlyOwner
    {
        stakeholderInfo[_stkAddress].penaltyWei = _penaltyWei;
    }

    function fund() public payable onlyOwner {}

    function viewBalance() public view returns (uint256) {
        return address(this).balance;
    }

    // STAKEHOLDER FUNCTIONS //
    // add a new device to the available devices mapping (only the producer can perform this action)
    function addNewDevice(string memory _UID, bool _returnToProducer)
        public
        onlyAllowedStakeholders([1, 0, 0, 0, 0])
    {
        devices[_UID] = Device(
            _UID,
            msg.sender,
            _returnToProducer,
            DeviceType.Usable
        );
        addDeviceToList(_UID, msg.sender);
    }

    // add stakeholder partners
    function addStkPartner(address _stkAddress)
        public
        onlyAllowedStakeholders([1, 1, 1, 1, 1])
        isPartnerTypeAllowed(_stkAddress)
    {
        // check if they are already partners
        require(
            stakeholderPartners[msg.sender][_stkAddress] != true,
            "You are already partners with this stakeholder!"
        );
        stakeholderPartners[msg.sender][_stkAddress] = true;
        // line below for demonstration purposes only
        // under normal circumstances the other party should accept the request
        stakeholderPartners[_stkAddress][msg.sender] = true;
    }

    // remove stakeholder partners
    function removeStkPartner(address _stkAddress)
        public
        onlyAllowedStakeholders([1, 1, 1, 1, 1])
    {
        // check if they are partners
        require(
            stakeholderPartners[msg.sender][_stkAddress],
            "You are not partners with this stakeholder!"
        );
        delete stakeholderPartners[msg.sender][_stkAddress];
        delete stakeholderPartners[_stkAddress][msg.sender];
    }

    // collection centers and producers can decide whether a device is usable or not
    function setDeviceType(string memory _UID, DeviceType _deviceType)
        public
        onlyAllowedStakeholders([1, 0, 1, 0, 0])
    {
        // check if msg sender owns the device
        require(
            devices[_UID].owner == msg.sender,
            "You don't own this device!"
        );
        // if _deviceType not equal to devices[_UID].deviceType
        if (devices[_UID].deviceType != _deviceType) {
            // remove device from list of devices owned by the stakeholder
            removeDeviceFromList(_UID, msg.sender);
            // set device type
            devices[_UID].deviceType = _deviceType;
            // add device to list of devices owned by the stakeholder
            addDeviceToList(_UID, msg.sender);
        }
    }

    // 2-PARTY FUNCTIONS //

    // transfer device ownership
    // NOTE: removed modifier: onlyAllowedStakeholders([1, 1, 1, 0, 1])
    function transferDeviceOwnership(string memory _UID, address _newOwner)
        private
    {
        removeDeviceFromList(_UID, devices[_UID].owner);
        devices[_UID].owner = _newOwner;
        addDeviceToList(_UID, _newOwner);
    }

    function producerToRetailer(string memory _UID)
        public
        onlyAllowedStakeholders([0, 1, 0, 0, 0])
        arePartners(devices[_UID].owner)
    {
        // check if the device owner is an authorized producer
        // and are partners with the retailer
        require(
            (stakeholderInfo[devices[_UID].owner].stkType ==
                StkTypes.Producer) &&
                (stakeholderPartners[devices[_UID].owner][msg.sender]),
            "Device owner is not a producer or you are not partners!"
        );
        transferDeviceOwnership(_UID, msg.sender);
    }

    function retailerToConsumer(string memory _UID) public {
        require(
            stakeholderInfo[devices[_UID].owner].stkType == StkTypes.Retailer,
            "Device not owned by a retailer!"
        );
        transferDeviceOwnership(_UID, msg.sender);
    }

    function consumerToRetailer(string memory _UID, address _address)
        public
        payable
    {
        // require that the address is an authorized retailer
        require(
            stakeholderInfo[_address].stkType == StkTypes.Retailer,
            "Device receiver is not a retailer or is not authorized!"
        );
        // check if msg sender is the device owner
        require(
            devices[_UID].owner == msg.sender,
            "You don't own this device!"
        );
        transferDeviceOwnership(_UID, _address);
        msg.sender.transfer(_REWARD_);
    }

    function consumerToSmartBin(string memory _UID, address _address)
        public
        payable
    {
        require(
            stakeholderInfo[_address].stkType == StkTypes.SmartBin,
            "Device receiver is not a smart bin or is not authorized!"
        );
        // check if msg sender is the device owner
        require(
            devices[_UID].owner == msg.sender,
            "You don't own this device!"
        );
        transferDeviceOwnership(_UID, _address);
        msg.sender.transfer(_REWARD_);
    }

    function toCollectionCenter(string memory _UID, address _address)
        public
        onlyAllowedStakeholders([1, 1, 0, 0, 1])
        arePartners(_address)
    {
        // check if msg sender is the device owner
        require(
            devices[_UID].owner == msg.sender,
            "You don't own this device!"
        );
        // if msg sender is producer
        if (stakeholderInfo[msg.sender].stkType == StkTypes.Producer) {
            // set device type to Ewaste
            setDeviceType(_UID, DeviceType.Ewaste);
        }
        transferDeviceOwnership(_UID, _address);
    }

    function collectionCenterToProducer(string memory _UID, address _address)
        public
        onlyAllowedStakeholders([0, 0, 1, 0, 0])
        arePartners(_address)
    {
        // check if msg sender is the device owner
        require(
            devices[_UID].owner == msg.sender,
            "You don't own this device!"
        );
        transferDeviceOwnership(_UID, _address);
    }

    function collectionCenterToRecyclingUnit(
        string memory _UID,
        address _address
    ) public onlyAllowedStakeholders([0, 0, 1, 0, 0]) arePartners(_address) {
        // check if msg sender is the device owner
        require(
            devices[_UID].owner == msg.sender,
            "You don't own this device!"
        );
        transferDeviceOwnership(_UID, _address);
    }

    // GENERAL FUNCTIONS //

    // add existing device to the stakeholder's list of devices
    function addDeviceToList(string memory _UID, address _address) private {
        if (devices[_UID].deviceType == DeviceType.Usable) {
            ownedDevices[_address].usableDevices.push(_UID);
            ownedDevices[_address].usableCount++;
        } else if (devices[_UID].deviceType == DeviceType.Ewaste) {
            ownedDevices[_address].ewasteDevices.push(_UID);
            ownedDevices[_address].ewasteCount++;
        }
    }

    // remove a device from the stakeholder's list of devices
    function removeDeviceFromList(string memory _UID, address _address)
        private
    {
        // pick correct list
        if (devices[_UID].deviceType == DeviceType.Usable) {
            uint256 tempCount = ownedDevices[_address].usableCount;
            for (uint256 index = 0; index < tempCount; index++) {
                if (
                    keccak256(
                        bytes(ownedDevices[_address].usableDevices[index])
                    ) == keccak256(bytes(_UID))
                ) {
                    ownedDevices[_address].usableDevices[index] = ownedDevices[
                        _address
                    ].usableDevices[tempCount - 1];
                    ownedDevices[_address].usableDevices.pop();
                    ownedDevices[_address].usableCount--;
                    break;
                }
            }
        } else if (devices[_UID].deviceType == DeviceType.Ewaste) {
            uint256 tempCount = ownedDevices[_address].ewasteCount;
            for (uint256 index = 0; index < tempCount; index++) {
                if (
                    keccak256(
                        bytes(ownedDevices[_address].ewasteDevices[index])
                    ) == keccak256(bytes(_UID))
                ) {
                    ownedDevices[_address].ewasteDevices[index] = ownedDevices[
                        _address
                    ].ewasteDevices[tempCount - 1];
                    ownedDevices[_address].ewasteDevices.pop();
                    ownedDevices[_address].ewasteCount--;
                    break;
                }
            }
        }
    }
}
