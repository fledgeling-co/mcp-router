using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Foundation;

namespace MCPRouter.Shell.Views;

/// <summary>
/// A panel that lays its children out left to right and wraps to a new row at the edge - the
/// harness tally's home.
///
/// WinUI ships no WrapPanel, and the control that sounds like one (<c>ItemsWrapGrid</c>) is a
/// virtualization panel that refuses to host outside a <c>ListViewBase</c>, so it cannot lay out
/// eight toggle buttons in a strip. This is the small version of the job: measure every child
/// unconstrained, wrap when the next one would cross the available width, arrange in the same
/// order. It is not virtualized, and does not need to be - the tally holds one button per
/// harness the window actually contains (§3.1), which is a handful, not a list.
/// </summary>
internal sealed class ActivityWrapPanel : Panel
{
    private const double ItemSpacing = 8;
    private const double RowSpacing = 8;

    protected override Size MeasureOverride(Size availableSize)
    {
        var x = 0.0;
        var rowHeight = 0.0;
        var height = 0.0;
        var width = 0.0;

        foreach (var child in Children)
        {
            child.Measure(new Size(double.PositiveInfinity, double.PositiveInfinity));
            var size = child.DesiredSize;

            if (x > 0 && double.IsFinite(availableSize.Width) && x + size.Width > availableSize.Width)
            {
                height += rowHeight + RowSpacing;
                x = 0;
                rowHeight = 0;
            }

            x += size.Width + ItemSpacing;
            rowHeight = Math.Max(rowHeight, size.Height);
            width = Math.Max(width, x - ItemSpacing);
        }

        return new Size(width, height + rowHeight);
    }

    protected override Size ArrangeOverride(Size finalSize)
    {
        var x = 0.0;
        var y = 0.0;
        var rowHeight = 0.0;

        foreach (var child in Children)
        {
            var size = child.DesiredSize;

            if (x > 0 && x + size.Width > finalSize.Width)
            {
                y += rowHeight + RowSpacing;
                x = 0;
                rowHeight = 0;
            }

            child.Arrange(new Rect(x, y, size.Width, size.Height));
            x += size.Width + ItemSpacing;
            rowHeight = Math.Max(rowHeight, size.Height);
        }

        return finalSize;
    }
}
