const { ethers } = require("hardhat");

async function main() {
    console.log("🚀 Deploying PokerGameSimple contract...");

    // Get deployer
    const [deployer] = await ethers.getSigners();
    console.log("📝 Deploying with account:", deployer.address);

    // Get balance
    const balance = await deployer.provider.getBalance(deployer.address);
    console.log("💰 Account balance:", ethers.formatEther(balance), "ETH");

    // Deploy contract
    const PokerGameSimple = await ethers.getContractFactory("PokerGameSimple");

    console.log("⏳ Deploying contract...");
    const pokerGame = await PokerGameSimple.deploy();

    console.log("⌛ Waiting for deployment confirmation...");
    await pokerGame.waitForDeployment();

    const contractAddress = await pokerGame.getAddress();
    console.log("✅ PokerGameSimple deployed to:", contractAddress);

    // Verify contract setup
    console.log("🔍 Verifying contract setup...");

    try {
        const totalGames = await pokerGame.getTotalGames();
        console.log("📊 Total games:", totalGames.toString());

        const gameCounter = await pokerGame.gameCounter();
        console.log("🎮 Game counter:", gameCounter.toString());

        // Test creating a game
        console.log("🎲 Testing game creation...");
        const tx = await pokerGame.createGame(0, 4, ethers.parseEther("0.01"));
        await tx.wait();
        console.log("✅ Test game created successfully!");

        const newTotalGames = await pokerGame.getTotalGames();
        console.log("📊 Total games after test:", newTotalGames.toString());

    } catch (error) {
        console.log("⚠️ Contract setup verification failed:", error.message);
    }

    console.log("\\n📋 Contract Deployment Summary:");
    console.log("================================");
    console.log("Contract Address:", contractAddress);
    console.log("Network:", network.name);
    console.log("Deployer:", deployer.address);
    console.log("\\n🔗 Add this address to your frontend:");
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