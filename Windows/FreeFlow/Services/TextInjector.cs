using System;
using System.Threading;
using System.Windows;
using WindowsInput;

namespace FreeFlow.Services;

public class TextInjector
{
    private readonly InputSimulator _inputSimulator;

    public TextInjector()
    {
        _inputSimulator = new InputSimulator();
    }

    public void PasteText(string text)
    {
        if (string.IsNullOrEmpty(text)) return;

        // Run on UI thread because of Clipboard
        Application.Current.Dispatcher.Invoke(() =>
        {
            try
            {
                // Save current clipboard
                var oldData = Clipboard.GetDataObject();

                // Set new text
                Clipboard.SetText(text);

                // Wait a bit for clipboard to settle
                Thread.Sleep(100);

                // Simulate Ctrl+V
                _inputSimulator.Keyboard.ModifiedKeyStroke(VirtualKeyCode.CONTROL, VirtualKeyCode.VK_V);

                // Wait a bit for the app to process the paste before restoring clipboard
                Thread.Sleep(500);

                // Restore clipboard
                if (oldData != null)
                {
                    Clipboard.SetDataObject(oldData);
                }
            }
            catch (Exception ex)
            {
                // Log or handle error
                Console.WriteLine($"Paste failed: {ex.Message}");
            }
        });
    }
}
