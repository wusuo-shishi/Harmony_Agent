import localUnitTest from './LocalUnit.test';
import agentUnitTest from './AgentUnit.test';

export default function testsuite() {
  localUnitTest();
  agentUnitTest();
}
