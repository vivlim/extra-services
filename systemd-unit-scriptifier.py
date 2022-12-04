import argparse
import configparser
import os

parser = argparse.ArgumentParser(description='Read a systemd unit file and produce a shellscript that approximates running it.')
parser.add_argument('--unit', help='Path to the unit file to read.', required=True)
parser.add_argument('--out', help='Where to write the result.', required=True)
parser.add_argument('--interpreter', help='Absolute path to shell', required=False, default="/bin/sh")

args = parser.parse_args()

# global state modified as we traverse the file
unit = {
    "env": [],
    "execStartPre": []
}

def handle_directive(key, value, section):
    print(f"key {key} and section {section}")
    if section == "Service" and key == "Environment":
        unit["env"].append(value.strip("\""))
    elif section == "Service" and key == "ExecStartPre":
        unit["execStartPre"].append(value)
    else:
        if section in unit.keys():
            unit[section][key] = value
        else:
            unit[section] = {
                key: value
            }

def write_script(target_path, interpreter):
    unit_name = os.path.basename(args.unit).replace(".service", "")
    with open(target_path, 'w') as f:
        f.write(f"#!{interpreter}\n")

        mkdir_and_set_env_var(f, f"/run/{unit_name}", "RUNTIME_DIRECTORY")
        mkdir_and_set_env_var(f, f"/var/lib/{unit_name}", "STATE_DIRECTORY")
        mkdir_and_set_env_var(f, f"/var/cache/{unit_name}", "CACHE_DIRECTORY")
        mkdir_and_set_env_var(f, f"/var/logs/{unit_name}", "LOGS_DIRECTORY")
        mkdir_and_set_env_var(f, f"/etc/{unit_name}", "CONFIGURATION_DIRECTORY")

        if "User" in unit["Service"]:
            # set a login shell for the account so we can run commands as them
            username = unit["Service"]["User"]
            f.write(f"\necho setting login shell for {username} to /bin/sh so commands can be run as them\n")
            f.write(f"chsh {username} -s /bin/sh\n\n")


        # write exports
        f.writelines([f"export {e}\n" for e in unit["env"]])

        write_directive(f, "Service", "WorkingDirectory", "echo WorkingDirectory='%s'")
        write_directive(f, "Service", "WorkingDirectory", "cd %s")
        write_exit_if_last_command_failed(f, f"changing to working directory")

        f.write("echo 'Running ExecStartPre commands'\n")
        for pre in unit["execStartPre"]:
            f.write(wrap_command(pre))
            write_exit_if_last_command_failed(f, f"command: {pre}")

        write_directive(f, "Service", "ExecStart", "echo 'Running ExecStart %s'")
        write_directive(f, "Service", "ExecStart", "%s", value_transformer=wrap_command)
        write_exit_if_last_command_failed(f, f"running ExecStart")

def write_directive(f, section, key, format, add_newline=True, throw_if_missing=False, value_transformer=None):
    if section in unit.keys() and key in unit[section]:
        value = unit[section][key]
        if value_transformer:
            value = value_transformer(value)
        f.write(format % value)
        if add_newline:
            f.write("\n")
    elif throw_if_missing:
        raise Exception(f"Missing required key {key} in section {section}")

def wrap_command(command):
    if command[0] == "@":
        raise Exception(f"@ executable prefix not handled, and has significant behavior change")

    if command[0] == "-":
        # suppress error code
        command = f"{command}; (exit 0);"

    command = command.lstrip("@-:+!")
    if "User" in unit["Service"]:
        username = unit["Service"]["User"]
        return f"/bin/su {username} <<'EOSUWRAPPEDCMD'\n{command}\nEOSUWRAPPEDCMD"
    else:
        return command

def write_exit_if_last_command_failed(f, message):
    f.write("\n")
    f.write("if [ $? -ne 0 ]\nthen\n")
    f.write("  export FATAL_ERR=$?\n")
    f.write(f"  echo \"Non-zero exit code $FATAL_ERR. {message}\"\n")
    f.write("   exit $FATAL_ERR\n\n")
    f.write("fi\n")

def mkdir_and_set_env_var(f, path, env_var_name):
    f.write("\n")
    f.write(f"mkdir -p {path}\n")
    write_exit_if_last_command_failed(f, f"mkdir {path} for {env_var_name}")
    f.write(f"export {env_var_name}={path}\n")
    f.write(f"echo {env_var_name}={path}\n")
    if "User" in unit["Service"]:
        username = unit["Service"]["User"]
        f.write(f"chown {username} {path}\n")

    f.write("\n")


def traverse_unit(unit_path):
    with open(unit_path) as f:
        line_num = 1
        section = ""
        for line in f:
            try:
                line = line.strip()
                if len(line) == 0:
                    continue
                if line.startswith("[") and line.endswith("]"):
                    section = line.strip("[]")
                    continue
                key, value = line.split('=', 1)
                handle_directive(key, value, section)
            except Exception as e:
                print(f"line {line_num} \"{line}\" skipped: {e}")
            finally:
                line_num = line_num + 1

traverse_unit(args.unit)
write_script(args.out, args.interpreter)

print(unit)
