pragma solidity 0.8.18;

interface IGaugeFactory {
    function createGauge(address, address, address, address, bool, address[] memory) external returns (address);
}
