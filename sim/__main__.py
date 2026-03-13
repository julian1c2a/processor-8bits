"""sim/__main__.py — Punto de entrada: python -m sim"""
from .cli import CLI

def main():
    CLI().run()

if __name__ == '__main__':
    main()
