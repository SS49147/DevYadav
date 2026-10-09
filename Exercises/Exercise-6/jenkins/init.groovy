import jenkins.model.Jenkins
import jenkins.install.InstallState
import hudson.security.HudsonPrivateSecurityRealm
import hudson.security.FullControlOnceLoggedInAuthorizationStrategy

def instance = Jenkins.get()
def realm = new HudsonPrivateSecurityRealm(false)
def secret = new File(System.getenv('JENKINS_ADMIN_PASSWORD_FILE')).text.trim()
realm.createAccount('admin', secret)
instance.setSecurityRealm(realm)
def authorization = new FullControlOnceLoggedInAuthorizationStrategy()
authorization.setAllowAnonymousRead(false)
instance.setAuthorizationStrategy(authorization)
instance.setNumExecutors(1)
instance.setSlaveAgentPort(-1)
instance.setInstallState(InstallState.INITIAL_SETUP_COMPLETED)
instance.save()
