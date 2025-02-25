# preflight 

A simple shell script to modularly add tests to run against a kubernetes cluster. 

```
chmod +x preflight.sh
./preflight.sh
```

To add a new test, add a new function at the bottom of the "Built-in Test Functions" section:

```
check_your_test() {
    # Test logic here
    echo "STATUS|Your message"
}
```

Register it in the TESTS array:

`TESTS+=("check_your_test")`
