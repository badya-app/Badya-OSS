# Contributing to Badya

Thank you for your interest in contributing to Badya, an open-source AI-powered language learning platform!

## Code of Conduct

Please be respectful, constructive, and inclusive to everyone participating in our community.

## Development Workflow

1. **Fork the repository** on GitHub.
2. **Clone your fork** locally:
   ```bash
   git clone https://github.com/<your-username>/Badya.git
   cd Badya
   ```
3. **Create a branch** for your feature or bugfix:
   ```bash
   git checkout -b feature/my-new-feature
   ```
4. **Make changes and test**:
   - For backend (Python / FastAPI / ADK):
     ```bash
     cd AI
     python -m venv .venv
     source .venv/bin/activate
     pip install -r requirements.txt
     pytest
     ```
   - For frontend (Flutter):
     ```bash
     cd Frontend/badya_app
     flutter pub get
     flutter analyze
     flutter test
     ```
5. **Commit your changes**:
   Write clear, concise commit messages.
6. **Submit a Pull Request** against the `main` branch.

## Coding Standards

- **Dart/Flutter**: Follow standard Dart style conventions (`flutter format .` and `flutter analyze`).
- **Python**: Follow PEP 8 guidelines (`ruff check .` / `ruff format .`).
- **Secrets & Sensitive Info**: Never commit production API keys, service account JSON files, or sensitive credentials. Always use environment variables or `.env.example`.
