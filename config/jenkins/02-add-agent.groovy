import hudson.model.*
import hudson.slaves.*
import jenkins.model.Jenkins
import hudson.slaves.JNLPLauncher

// Define a "Permanent Agent" Slave
def agent1 = new DumbSlave(
    "agent1", // Node name
    "/home/jenkins/agent", // Remote filesystem root
    new JNLPLauncher(true) // Correct class name is JNLPLauncher
)

agent1.nodeDescription = "Docker agent node"
agent1.numExecutors = 1
agent1.labelString = "agent-node-docker"
agent1.mode = Node.Mode.NORMAL
agent1.retentionStrategy = new RetentionStrategy.Always()

// Define a "Permanent Agent 2" Slave
def agent2 = new DumbSlave(
    "agent2", // Node name
    "/home/jenkins/agent", // Remote filesystem root
    new JNLPLauncher(true) // Correct class name is JNLPLauncher
)
agent2.nodeDescription = "Docker agent node"
agent2.numExecutors = 1
agent2.labelString = "agent-node-docker"
agent2.mode = Node.Mode.NORMAL
agent2.retentionStrategy = new RetentionStrategy.Always()

// Create a "Permanent Agent"
Jenkins.instance.addNode(agent1)
Jenkins.instance.addNode(agent2)

println "Nodes has been created successfully."