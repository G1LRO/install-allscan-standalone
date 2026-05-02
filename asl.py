import fastapi
from pydantic import BaseModel, field_validator
from server.routes.wifi import custom_generate_unique_id
from server.utils.subprocess_runner import run_sudo_command

CONFIGURE_ASL_SCRIPT = "/home/rln/configure-asl3.sh"

class ASLConfig(BaseModel):
    node_number: str
    node_password: str
    callsign: str
    login_password: str

    @field_validator('node_number', 'node_password', 'callsign', 'login_password')
    @classmethod
    def trim_whitespace(cls, v: str) -> str:
        return v.strip()

class ASLStatus(BaseModel):
    node_number: str | None = None
    callsign: str | None = None

class ASLResult(BaseModel):
    success: bool
    message: str
    error: str | None = None

router = fastapi.APIRouter(
    prefix="/api/asl", generate_unique_id_function=custom_generate_unique_id
)

def configure_asl3(node_number: str, callsign: str, node_password: str, login_password: str) -> tuple[bool, str]:
    """Run configure-asl3.sh script.
    
    node_password  — AllStarLink registration password (for ASL3 config)
    login_password — User-chosen login password (for AllScan, allmon3, Linux user)
    """
    result = run_sudo_command(
        [CONFIGURE_ASL_SCRIPT,
         "-n", node_number,
         "-c", callsign,
         "-p", node_password,
         "-w", login_password],
        timeout=60,
    )
    if result.success:
        return True, "ASL3 configured"
    return False, result.stderr or result.stdout

def set_allmon3_password(password: str) -> tuple[bool, str]:
    """Set allmon3 password for rln user"""
    result = run_sudo_command(["allmon3-passwd", "--password", password, "rln"])
    if result.success:
        return True, "Allmon3 password set"
    return False, result.stderr

def restart_allmon3() -> tuple[bool, str]:
    """Restart allmon3 service"""
    result = run_sudo_command(["systemctl", "restart", "allmon3"])
    if result.success:
        return True, "Allmon3 restarted"
    return False, result.stderr

def set_rln_user_password(password: str) -> tuple[bool, str]:
    """Set rln user system password using chpasswd"""
    result = run_sudo_command(
        ["chpasswd"],
        input_text=f"rln:{password}\n",
    )
    if result.success:
        return True, "User password set"
    return False, result.stderr

@router.get("")
def get_asl_status() -> ASLStatus:
    """Get current ASL status (passwords not returned)"""
    return ASLStatus()

@router.post("")
def set_asl(config: ASLConfig) -> ASLResult:
    """Configure ASL: run configure script, restart services, set passwords.
    NOTE: Asterisk restart is handled by display_driver.service, not here.
    """
    errors = []

    # Step 1: Run configure-asl3.sh (also handles AllScan password via -w)
    success, msg = configure_asl3(
        config.node_number, config.callsign, config.node_password, config.login_password
    )
    if not success:
        errors.append(f"configure-asl3: {msg}")

    # Step 2: Set allmon3 password
    success, msg = set_allmon3_password(config.login_password)
    if not success:
        errors.append(f"allmon3 password: {msg}")

    # Step 3: Restart allmon3
    success, msg = restart_allmon3()
    if not success:
        errors.append(f"allmon3 restart: {msg}")

    # Step 4: Set rln user password
    success, msg = set_rln_user_password(config.login_password)
    if not success:
        errors.append(f"user password: {msg}")

    if not errors:
        return ASLResult(success=True, message="ASL configured successfully")
    else:
        return ASLResult(
            success=False,
            message="ASL configuration had errors",
            error="; ".join(errors),
        )
