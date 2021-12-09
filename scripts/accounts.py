#!/usr/bin/env python3

import csv
import pwd
import grp
import secrets
import string
import os
import crypt
import sys
import json
from pathlib import Path

def AssignFromSeries(name, default_value, series):
    if name in series:
        return series[name]
    else:
        return default_value



def AccountExists(name):
    try:
        pwd.getpwnam(name)
    except KeyError:
        return False

    return True



def GroupExists(name):
    try:
        grp.getgrnam(name)
    except KeyError:
        return False

    return True


def GeneratePassword():
    # Our first preference is to use word-based passwords, if /usr/share/dict/words exists:
    #if os.path.exists('/usr/share/dict/words'):
    #    with open('/usr/share/dict/words') as wordlist:
    #        words = [word.strip().capitalize() for word in wordlist]
    #        password = ''.join(secrets.choice(words) for i in range(2))
    #        #numbers = password.join(str(secrets.randbelow(1000)))
    #        numbers = secrets.randbelow(1000)
    #        print("password: ", password)
    #        print("numbers: ", numbers)
    #        return password

    # Otherwise, use random characters:
    alphabet = string.ascii_letters + string.digits
    password = ''.join(secrets.choice(alphabet) for i in range(10))
    return password



    



def AddUser(userdata):
    valid = False

    # Convert the column names to a list:
    userinfo = userdata.index.tolist()

    # Assign variables, using defaults if not present:
    account = AssignFromSeries('Account', '',         userdata)
    group   = AssignFromSeries('Group',   'users',    userdata)
    name    = AssignFromSeries('Name',    '',         userdata)
    shell   = AssignFromSeries('Shell',   'bash',     userdata)
    method  = AssignFromSeries('Method',  'Password', userdata)
    data    = AssignFromSeries('Data',    '',         userdata)

    # If account is valid (we have an account name, and it doesn't already exist), add it:
    if account and not AccountExists(account):
        # First, if the group doesn't exist, add it:
        if not GroupExists(group):
            command = "groupadd " + group
            os.system(command)

        # Check if the shell is either 'bash' or 'tcsh', or '/bin/bash', or '/bin/tcsh'
        # If it's the first two, set it to the full form:
        if shell in ['bash', 'tcsh']:
            shell = "/bin/" + shell
        if shell not in ['/bin/bash', '/bin/tcsh']:
            return

        # Next, check that we have a valid method - otherwise we default to password:
        if method not in ['Password', 'PublicKey']:
            method = 'Password'

        # If we're using a password, check if we have a supplied one in data, otherwise generate one:
        if method == 'Password':
            if not data:
                data = GeneratePassword()

        # Set up some simple aliases:
        homedir  = "/home/"+account

        # Create the command, bit by bit:
        command = "adduser " + account + " "
        command += "-c '" + name + "' "
        command += "-d " + homedir + " "
        command += "-g " + group + " "
        command += "-s " + shell + " "

        # If we have a Password, add the password line, otherwise, add a command to insert the key:
        if method == 'Password':
            command += "-p " + crypt.crypt(data) + " "
        else:
            sshdir = "/home/" + account + "/.ssh"
            command += "; mkdir " + sshdir
            command += "; echo '" + data + "' >> " + sshdir + "/authorized_keys"
            command += "; chmod 0700 " + sshdir
            command += "; chmod 0600 " + sshdir + "/authorized_keys"
            command += "; chown -R " + account + ":" + group + " " + sshdir
            os.system(command)


def apply_defaults(username, data):
    # Here's where we standardize the format, applying defaults to data for easier processing
    print("Name.. -> ", data)
    #if 'Password' in data:
    #    print("Got 'Password': ", data['Password'])

    if not 'Group' in data:
        data['Group'] = 'users'
    if not data['Group']:
        data['Group'] = 'users'

    # Add users:
    password = GeneratePassword()
    #print("Username: ", username, " -> ", password)

    # Set up some simple aliases:
    homedir  = "/home/"+username
    fullname = data['First'] + " " + data['Last']

    # Create the command, bit by bit:
    command = "adduser " + username + " "
    command += "-c '" + fullname + "' "
    command += "-d " + homedir + " "
    command += "-g " + 'users'  + " "
    command += "-s " + "/bin/bash" + " "
    command += "-p '" + crypt.crypt(password) + "' "
    os.system(command)
    lnscratch = "runuser -l " + username + " -c 'mkdir /scratch/" + username + " ; ln -s /scratch/" + username + " ~/scratch"
    os.system(lnscratch)
    sshcmd = "runuser -l " + username + " -c 'ssh-keygen

    if data['Group'] == 'admin':
        sudoers_file = open('/etc/sudoers.d/98-cesm-admin', 'a')
        sudoers_file.write(username + " ALL=(ALL) NOPASSWD:ALL \n")

    logname = os.path.expanduser('~')+'/users.log'
    with open(logname, 'a') as logfile:
        #print(username, " (", fullname, ")  : ", password)
        logfile.write(username + ":" + password + " (" + fullname + ")\n")

def configure(data):
    try:
        for username in data['accounts']:
            #account_data = data['accounts'][account]
            #validate(data['accounts'][account]) # Need to try/except here later?
            accountdata = data['accounts'][username]
            apply_defaults(username, accountdata)
            #print("Account: ", data['accounts'][account])
            #apply_defaults(
    except Exception as e:
        print("No account data found in data: '",data)



def accounts(argument):
    # Arguments can be either files or strings - process each accordingly into JSON:
    # File version:
    if os.path.isfile(argument):
        with open(argument) as f:
            try:
                data = json.load(f)
            except Exception as e:
                print("Error processing '", argument, "' -> ", e)
            else:
                configure(data)

    # String version
    else:
        try:
            data = json.loads(argument)
        except Exception as e:
            print("Error processing '", argument, "' -> ", e)
        else:
            configure(data)


def csv_to_json(csvfile):
    # create a dictionary
    fulldata = {}
    fulldata['accounts'] = {}
    data = fulldata['accounts']
     
    # Open a csv reader called DictReader
    with open(csvfile, encoding='utf-8') as handle:
        csvdata = csv.DictReader(handle)

        # Convert each row into a dictionary
        # and add it to data
        for row in csvdata:
             
            # Make our key by a username from the name
            #print("row: ", row)
            first = row['First']
            last = row['Last']
            email = row['Email']
            username = (first[0]+last).lower()
            if username in data:
                print("Error: Duplicate name; need to handle this...")

            print("Username: ", username)
            data[username] = row

    return fulldata
         

def main():
    # Loop over the arguments, passing them to the accounts function:
    for argument in sys.argv[1:]:
        if os.path.isfile(argument):
            if Path(argument).suffix == '.csv':
                jsondata = csv_to_json(argument)
                print("Dump:", json.dumps(jsondata, indent=4))
                #accounts(jsondata)
                configure(jsondata)


if __name__ == "__main__":
    main()

