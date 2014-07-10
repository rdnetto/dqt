import dqt.qtcore;
import dqt.qtgui;

int main() {
    import core.runtime;
    import std.stdio;

    auto cArgs = Runtime.cArgs;

    auto app = new QApplication(cArgs.argc, cArgs.argv);

    auto widget = new QLabel("Hello World!");

    widget.show();

    return QApplication.exec();
}
