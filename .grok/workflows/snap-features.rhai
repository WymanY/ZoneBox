let meta = #{
    name: "snap-features",
    description: "Verify Shake to Snap, Quick Snapper, grid draw-rectangle, and magnetic resize",
    phases: [
        #{ title: "Test", detail: "make test twice" },
        #{ title: "Build", detail: "make build" },
    ],
};

let root = if args == () { () } else { args.root };
if root == () { pause("verification", "Pass args.root — the ZoneBox repo path."); }

phase("Test");
let test_prompt = "In " + root + " run `make project` then `make test`. If tests fail, read the failures, fix the SHIPPED Core/app code (not the tests unless the test is wrong), and re-run until `make test` is green. Do not stub reducers. Write a short summary of what you ran.";
let t1 = agent(test_prompt, #{ label: "make-test", capability_mode: "all" });
if t1 == () || !t1.success {
    pause("verification", "make test agent failed; inspect and rerun /workflow snap-features.");
}

phase("Build");
let build_prompt = "In " + root + " run `make build` with CODE_SIGNING_ALLOWED=NO via the Makefile. If it fails, fix compile errors in the repo and rebuild. Summarize the result.";
let b1 = agent(build_prompt, #{ label: "make-build", capability_mode: "all" });
if b1 == () || !b1.success {
    pause("verification", "make build agent failed.");
}

complete(#{ summary: "snap-features verified", root: root });
