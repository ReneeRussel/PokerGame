const { ethers } = require("hardhat");

async function main() {
    console.log("🚀 Deploying PokerGame contract...");

    // Get deployer
    const [deployer] = await ethers.getSigners();
    console.log("📝 Deploying with account:", deployer.address);

    // Get balance
    const balance = await deployer.provider.getBalance(deployer.address);
    console.log("💰 Account balance:", ethers.formatEther(balance), "ETH");

    // Deploy contract
    const PokerGame = await ethers.getContractFactory("PokerGame");

    console.log("⏳ Deploying contract...");
    const pokerGame = await PokerGame.deploy();

    console.log("⌛ Waiting for deployment confirmation...");
    await pokerGame.waitForDeployment();

    const contractAddress = await pokerGame.getAddress();
    console.log("✅ PokerGame deployed to:", contractAddress);

    // Verify contract setup
    console.log("🔍 Verifying contract setup...");

    try {
        const totalGames = await pokerGame.getTotalGames();
        console.log("📊 Total games:", totalGames.toString());

        const gameCounter = await pokerGame.gameCounter();
        console.log("🎮 Game counter:", gameCounter.toString());

    } catch (error) {
        console.log("⚠️ Contract setup verification failed:", error.message);
    }

    console.log("\n📋 Contract Deployment Summary:");
    console.log("================================");
    console.log("Contract Address:", contractAddress);
    console.log("Network:", network.name);
    console.log("Deployer:", deployer.address);
    console.log("\n🔗 Add this address to your frontend:");
    console.log(`const CONTRACT_ADDRESS = "${contractAddress}";`);

    return contractAddress;
}

// Handle script execution
if (require.main === module) {
    main()
        .then((address) => {
            console.log("Deployment completed successfully!");
            process.exit(0);
        })
        .catch((error) => {
            console.error("Deployment failed:", error);
            process.exit(1);
        });
}

module.exports = { main };