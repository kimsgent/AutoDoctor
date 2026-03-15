# Contributing to AutoDoctor

Thank you for considering contributing! Your help improves AutoDoctor for everyone and ensures reliable diagnostics and remediation for Windows systems.

---

## 1. Getting Started

1. **Fork the repository** on GitHub:
   [https://github.com/kimsgent/AutoDoctor](https://github.com/kimsgent/AutoDoctor)

2. **Clone your fork locally**:

   ```bash
   git clone https://github.com/kimsgent/AutoDoctor.git
   cd AutoDoctor
   ```

3. **Create a virtual environment** (Python 3.12 recommended) and install dependencies:

   ```bash
   cd .\server\api
   python -m venv .venv
   .\.venv\Scripts\Activate.ps1
   python -m pip install --upgrade pip
   pip install -r requirements.txt
   ```

---

## 2. Making Changes

* **Create a feature branch** for your work:

  ```bash
  git checkout -b feature/my-feature
  ```
* Follow the existing **project structure and code style** (PowerShell modules, Python FastAPI service, dashboard scripts, etc.).
* Run diagnostics or dashboard tests to verify changes.

---

## 3. Committing and Pushing

* **Commit your changes** with clear messages:

  ```bash
  git add .
  git commit -m "Add feature XYZ"
  ```
* **Push your branch** to your fork:

  ```bash
  git push origin feature/my-feature
  ```

---

## 4. Pull Requests

1. Go to your fork on GitHub and click **Compare & pull request**.
2. Write a **descriptive title and summary** of your changes.
3. Submit the pull request to the **`main` branch** of AutoDoctor.

---

## 5. Reporting Issues

* Use the **Issues tab** on GitHub for bugs, suggestions, or questions.
* Include as much detail as possible (steps to reproduce, screenshots, environment info, Windows version, PowerShell version).

---

## 6. Code of Conduct

By contributing, you agree to follow the [Contributor Covenant Code of Conduct](https://www.contributor-covenant.org/).

---

Thank you for helping make AutoDoctor better! 🚀
